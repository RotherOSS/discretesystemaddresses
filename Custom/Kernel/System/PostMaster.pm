# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2023 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::System::PostMaster;

use strict;
use warnings;

use Kernel::System::EmailParser;
use Kernel::System::PostMaster::DestQueue;
use Kernel::System::PostMaster::NewTicket;
use Kernel::System::PostMaster::FollowUp;
use Kernel::System::PostMaster::Reject;

use Kernel::System::VariableCheck qw(IsHashRefWithData IsArrayRefWithData);

our %ObjectManagerFlags = (
    NonSingleton => 1,
);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DynamicField',
    'Kernel::System::Main',
    'Kernel::System::Queue',
    'Kernel::System::State',
    'Kernel::System::Ticket',
    'Kernel::System::Ticket::Article',
);

=head1 NAME

Kernel::System::PostMaster - postmaster lib

=head1 DESCRIPTION

All postmaster functions. E. g. to process emails.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $PostMasterObject = $Kernel::OM->Create(
        'Kernel::System::PostMaster',
        ObjectParams => {
            Email        => \@ArrayOfEmailContent,
            Trusted      => 1, # 1|0 ignore X-OTOBO header if false
        },
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    $Self->{Email}                  = $Param{Email}                  || die "Got no Email!";
    $Self->{CommunicationLogObject} = $Param{CommunicationLogObject} || die "Got no CommunicationLogObject!";

    $Self->{ParserObject} = Kernel::System::EmailParser->new(
        Email => $Param{Email},
    );

    # create needed objects
    $Self->{DestQueueObject} = Kernel::System::PostMaster::DestQueue->new( %{$Self} );
    $Self->{NewTicketObject} = Kernel::System::PostMaster::NewTicket->new( %{$Self} );
    $Self->{FollowUpObject}  = Kernel::System::PostMaster::FollowUp->new( %{$Self} );
    $Self->{RejectObject}    = Kernel::System::PostMaster::Reject->new( %{$Self} );

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check needed config options
    for my $Option (qw(PostmasterUserID PostmasterX-Header)) {
        $Self->{$Option} = $ConfigObject->Get($Option)
            || die "Found no '$Option' option in configuration!";
    }

    # should I use x-otobo headers?
    $Self->{Trusted} = defined $Param{Trusted} ? $Param{Trusted} : 1;

    if ( $Self->{Trusted} ) {

        # get dynamic field objects
        my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

        # add Dynamic Field headers
        my $DynamicFields = $DynamicFieldObject->DynamicFieldList(
            Valid      => 1,
            ObjectType => [ 'Ticket', 'Article' ],
            ResultType => 'HASH',
        );

        # create a lookup table
        my %HeaderLookup = map { $_ => 1 } @{ $Self->{'PostmasterX-Header'} };

        for my $DynamicField ( values %$DynamicFields ) {
            for my $Header (
                'X-OTOBO-DynamicField-' . $DynamicField,
                'X-OTOBO-FollowUp-DynamicField-' . $DynamicField,
                )
            {

                # only add the header if is not alreday in the config
                if ( !$HeaderLookup{$Header} ) {
                    push @{ $Self->{'PostmasterX-Header'} }, $Header;
                }
            }
        }
    }

    # get email params
    $Self->{EmailParams} = $Self->GetEmailParams();

    # get first communication log communication / connection id
    $Self->{FirstCommunicationID} = $Self->{CommunicationLogObject}->{CommunicationID};
    $Self->{FirstConnectionID}    = $Self->{CommunicationLogObject}->{Current}->{Connection};

    return $Self;
}

=head2 Run()

to execute the run process

    $PostMasterObject->Run(
        Queue   => 'Junk',  # optional, specify target queue for new tickets
        QueueID => 1,       # optional, specify target queue for new tickets
    );

return params

    0 = error (also false)
    1 = new ticket created
    2 = follow up / open/reopen
    3 = follow up / close -> new ticket
    4 = follow up / close -> reject
    5 = ignored (because of X-OTOBO-Ignore header)

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my @Return;

    # get email params
    my $GetParam = $Self->{EmailParams};

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check if follow up
    my ( $Tn, $TicketID ) = $Self->CheckFollowUp( GetParam => $GetParam );

    # check system addresses in pool
    if ( !$Self->{AddressCount} ) {

        # filter system addresses
        my @FilteredAddresses = $Self->_FilterSystemAddresses(
            ToString => $GetParam->{To},
        );
        if ( @FilteredAddresses ) {

            # set address count
            $Self->{AddressCount} = scalar @FilteredAddresses;

            # get objects
            my $LinkObject          = $Kernel::OM->Get('Kernel::System::LinkObject');
            my $TicketObject        = $Kernel::OM->Get('Kernel::System::Ticket');
            my $SystemAddressObject = $Kernel::OM->Get('Kernel::System::SystemAddress');

            # get mail queue id
            my $MailQueueID;
            if ( $TicketID ) {
                $MailQueueID = $TicketObject->TicketQueueID(
                    TicketID => $TicketID,
                );
            }

            my @GetTicketIDs;
            my $ToString = $GetParam->{To};
            for my $FilteredAddress ( @FilteredAddresses ) {

                # system address follow-up check
                my $AddressQueueID = $SystemAddressObject->SystemAddressQueueID( Address => $FilteredAddress );
                if (
                    ( $MailQueueID && $AddressQueueID )
                    &&
                    ( $MailQueueID != $AddressQueueID )
                ) {

                    # check linked tickets
                    my %LinkedTickets = $LinkObject->LinkKeyListWithData(
                        Object1   => 'Ticket',
                        Key1      => $TicketID,
                        Object2   => 'Ticket',
                        State     => 'Valid',
                        UserID    => $Self->{PostmasterUserID},
                    );

                    for my $LinkedTicket ( keys %LinkedTickets ) {

                        my $LTQueueID = $LinkedTickets{$LinkedTicket}{QueueID};
                        if ( $MailQueueID != $LTQueueID ) {
                            next;
                        }

                        # follow-up for linked ticket
                        my $LTTicketID = $LinkedTickets{$LinkedTicket}{TicketID};

                        $Kernel::OM->Get('Kernel::System::Log')->Dumper("LinkedTicket_QueueID: ", $LTQueueID);
                        $Kernel::OM->Get('Kernel::System::Log')->Dumper("LinkedTicket_TicketID: ", $LTTicketID);
                    }

                    # $Kernel::OM->Get('Kernel::System::Log')->Dumper("MailQueueID: ", $MailQueueID);
                    # $Kernel::OM->Get('Kernel::System::Log')->Dumper("AddressQueueID: ", $AddressQueueID);
                }

                my $GetTicketID = $Self->_RecursivePostMasterRun(
                    GetParam          => $GetParam,
                    ToString          => $ToString,
                    QueueID           => $Param{QueueID},
                    SystemPoolAddress => $FilteredAddress,
                );
                push (@GetTicketIDs, $GetTicketID);

                $Self->{AddressCount}--;
            }

            if ( @GetTicketIDs ) {

                $Self->_InterdivisionalTicketLinkAdd(
                    TicketIDs => \@GetTicketIDs,
                );
            }

            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'info',
                Message  => "SystemAddressPoolCheck finished!",
            );

            return 1;
        }
    }

    # run all PreFilterModules (modify email params)
    if ( ref $ConfigObject->Get('PostMaster::PreFilterModule') eq 'HASH' ) {

        my %Jobs = %{ $ConfigObject->Get('PostMaster::PreFilterModule') };

        # get main objects
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

        JOB:
        for my $Job ( sort keys %Jobs ) {

            return if !$MainObject->Require( $Jobs{$Job}->{Module} );

            my $FilterObject = $Jobs{$Job}->{Module}->new(
                %{$Self},
            );

            if ( !$FilterObject ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "new() of PreFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
                next JOB;
            }

            # modify params
            my $Run = $FilterObject->Run(
                GetParam  => $GetParam,
                JobConfig => $Jobs{$Job},
                TicketID  => $TicketID,
                UserID    => $Self->{PostmasterUserID},
            );
            if ( !$Run ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "Execute Run() of PreFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
            }
        }
    }

    # should I ignore the incoming mail?
    if ( $GetParam->{'X-OTOBO-Ignore'} && $GetParam->{'X-OTOBO-Ignore'} =~ /(yes|true)/i ) {
        $Self->{CommunicationLogObject}->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Info',
            Key           => 'Kernel::System::PostMaster',
            Value         =>
                "Ignored Email (From: $GetParam->{'From'}, Message-ID: $GetParam->{'Message-ID'}) "
                . "because the X-OTOBO-Ignore is set (X-OTOBO-Ignore: $GetParam->{'X-OTOBO-Ignore'}).",
        );
        return (5);
    }

    #
    # ticket section
    #

    # check if follow up (again, with new GetParam)
    ( $Tn, $TicketID ) = $Self->CheckFollowUp( GetParam => $GetParam );

    # run all PreCreateFilterModules
    if ( ref $ConfigObject->Get('PostMaster::PreCreateFilterModule') eq 'HASH' ) {

        my %Jobs = %{ $ConfigObject->Get('PostMaster::PreCreateFilterModule') };

        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

        JOB:
        for my $Job ( sort keys %Jobs ) {

            return if !$MainObject->Require( $Jobs{$Job}->{Module} );

            my $FilterObject = $Jobs{$Job}->{Module}->new(
                %{$Self},
            );

            if ( !$FilterObject ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "new() of PreCreateFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
                next JOB;
            }

            # modify params
            my $Run = $FilterObject->Run(
                GetParam  => $GetParam,
                JobConfig => $Jobs{$Job},
                TicketID  => $TicketID,
                UserID    => $Self->{PostmasterUserID},
            );
            if ( !$Run ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "Execute Run() of PreCreateFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
            }
        }
    }

    # check if it's a follow up ...
    if ( $Tn && $TicketID ) {

        # get ticket object
        my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

        # get ticket data
        my %Ticket = $TicketObject->TicketGet(
            TicketID      => $TicketID,
            DynamicFields => 0,
        );

        # get queue object
        my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

        # check if it is possible to do the follow up
        # get follow up option (possible or not)
        my $FollowUpPossible = $QueueObject->GetFollowUpOption(
            QueueID => $Ticket{QueueID},
        );

        # get lock option (should be the ticket locked - if closed - after the follow up)
        my $Lock = $QueueObject->GetFollowUpLockOption(
            QueueID => $Ticket{QueueID},
        );

        # get state details
        my %State = $Kernel::OM->Get('Kernel::System::State')->StateGet(
            ID => $Ticket{StateID},
        );

        # Check if we need to treat a bounce e-mail always as a normal follow-up (to reopen the ticket if needed).
        my $BounceEmailAsFollowUp = 0;
        if ( $GetParam->{'X-OTOBO-Bounce'} ) {
            $BounceEmailAsFollowUp = $ConfigObject->Get('PostmasterBounceEmailAsFollowUp');
        }

        # create a new ticket
        if ( !$BounceEmailAsFollowUp && $FollowUpPossible =~ /new ticket/i && $State{TypeName} =~ /^(removed|close)/i )
        {

            $Self->{CommunicationLogObject}->ObjectLog(
                ObjectLogType => 'Message',
                Priority      => 'Info',
                Key           => 'Kernel::System::PostMaster',
                Value         => "Follow up for [$Tn] but follow up not possible ($Ticket{State}). Create new ticket.",
            );

            # send mail && create new article
            # get queue if of From: and To:
            if ( !$Param{QueueID} ) {
                $Param{QueueID} = $Self->{DestQueueObject}->GetQueueID(
                    Params => $GetParam,
                );
            }

            # check if trusted returns a new queue id
            my $TQueueID = $Self->{DestQueueObject}->GetTrustedQueueID(
                Params => $GetParam,
            );
            if ($TQueueID) {
                $Param{QueueID} = $TQueueID;
            }

            # Clean out the old TicketNumber from the subject (see bug#9108).
            # This avoids false ticket number detection on customer replies.
            if ( $GetParam->{Subject} ) {
                $GetParam->{Subject} = $TicketObject->TicketSubjectClean(
                    TicketNumber => $Tn,
                    Subject      => $GetParam->{Subject},
                );
            }

            $TicketID = $Self->{NewTicketObject}->Run(
                InmailUserID     => $Self->{PostmasterUserID},
                GetParam         => $GetParam,
                QueueID          => $Param{QueueID},
                Comment          => "Because the old ticket [$Tn] is '$State{Name}'",
                AutoResponseType => 'auto reply/new ticket',
                LinkToTicketID   => $TicketID,
            );

            if ( !$TicketID ) {
                return;
            }

            @Return = ( 3, $TicketID );
        }

        # reject follow up
        elsif ( !$BounceEmailAsFollowUp && $FollowUpPossible =~ /reject/i && $State{TypeName} =~ /^(removed|close)/i ) {

            $Self->{CommunicationLogObject}->ObjectLog(
                ObjectLogType => 'Message',
                Priority      => 'Info',
                Key           => 'Kernel::System::PostMaster',
                Value         => "Follow up for [$Tn] but follow up not possible. Follow up rejected.",
            );

            # send reject mail and add article to ticket
            my $Run = $Self->{RejectObject}->Run(
                TicketID         => $TicketID,
                InmailUserID     => $Self->{PostmasterUserID},
                GetParam         => $GetParam,
                Lock             => $Lock,
                Tn               => $Tn,
                Comment          => 'Follow up rejected.',
                AutoResponseType => 'auto reject',
            );

            if ( !$Run ) {
                return;
            }

            @Return = ( 4, $TicketID );
        }

        # create normal follow up
        else {

            my $Run = $Self->{FollowUpObject}->Run(
                TicketID         => $TicketID,
                InmailUserID     => $Self->{PostmasterUserID},
                GetParam         => $GetParam,
                Lock             => $Lock,
                Tn               => $Tn,
                AutoResponseType => 'auto follow up',
            );

            if ( !$Run ) {
                return;
            }

            @Return = ( 2, $TicketID );
        }
    }

    # create new ticket
    else {

        if ( $Param{Queue} && !$Param{QueueID} ) {

            # queue lookup if queue name is given
            $Param{QueueID} = $Kernel::OM->Get('Kernel::System::Queue')->QueueLookup(
                Queue => $Param{Queue},
            );
        }

        # get queue from From: or To:
        if ( !$Param{QueueID} ) {
            $Param{QueueID} = $Self->{DestQueueObject}->GetQueueID( Params => $GetParam );
        }

        # check if trusted returns a new queue id
        my $TQueueID = $Self->{DestQueueObject}->GetTrustedQueueID(
            Params => $GetParam,
        );
        if ($TQueueID) {
            $Param{QueueID} = $TQueueID;
        }
        $TicketID = $Self->{NewTicketObject}->Run(
            InmailUserID     => $Self->{PostmasterUserID},
            GetParam         => $GetParam,
            QueueID          => $Param{QueueID},
            AutoResponseType => 'auto reply',
        );

        return if !$TicketID;

        @Return = ( 1, $TicketID );
    }

    # run all PostFilterModules (modify email params)
    if ( ref $ConfigObject->Get('PostMaster::PostFilterModule') eq 'HASH' ) {

        my %Jobs = %{ $ConfigObject->Get('PostMaster::PostFilterModule') };

        # get main objects
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

        JOB:
        for my $Job ( sort keys %Jobs ) {

            return if !$MainObject->Require( $Jobs{$Job}->{Module} );

            my $FilterObject = $Jobs{$Job}->{Module}->new(
                %{$Self},
            );

            if ( !$FilterObject ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "new() of PostFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
                next JOB;
            }

            # modify params
            my $Run = $FilterObject->Run(
                TicketID  => $TicketID,
                GetParam  => $GetParam,
                JobConfig => $Jobs{$Job},
                Return    => $Return[0],
                UserID    => $Self->{PostmasterUserID},
            );

            if ( !$Run ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "Execute Run() of PostFilterModule $Jobs{$Job}->{Module} not successfully!",
                );
            }
        }
    }

    return @Return;
}

=head2 CheckFollowUp()

to detect the ticket number in processing email

    my ($TicketNumber, $TicketID) = $PostMasterObject->CheckFollowUp(
        Subject => 'Re: [Ticket:#123456] Some Subject',
    );

=cut

sub CheckFollowUp {
    my ( $Self, %Param ) = @_;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get config objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # Load CheckFollowUp Modules
    my $Jobs = $ConfigObject->Get('PostMaster::CheckFollowUpModule');

    if ( IsHashRefWithData($Jobs) ) {
        my $MainObject = $Kernel::OM->Get('Kernel::System::Main');
        JOB:
        for my $Job ( sort keys %$Jobs ) {
            my $Module = $Jobs->{$Job};

            return if !$MainObject->Require( $Jobs->{$Job}->{Module} );

            my $CheckObject = $Jobs->{$Job}->{Module}->new(
                %{$Self},
            );

            if ( !$CheckObject ) {
                $Self->{CommunicationLogObject}->ObjectLog(
                    ObjectLogType => 'Message',
                    Priority      => 'Error',
                    Key           => 'Kernel::System::PostMaster',
                    Value         => "new() of CheckFollowUp $Jobs->{$Job}->{Module} not successfully!",
                );
                next JOB;
            }
            my $TicketID = $CheckObject->Run(
                %Param,
                UserID => $Self->{PostmasterUserID},
            );
            if ($TicketID) {
                my %Ticket = $TicketObject->TicketGet(
                    TicketID      => $TicketID,
                    DynamicFields => 0,
                );
                if (%Ticket) {

                    $Self->{CommunicationLogObject}->ObjectLog(
                        ObjectLogType => 'Message',
                        Priority      => 'Debug',
                        Key           => 'Kernel::System::PostMaster',
                        Value         =>
                            "Found follow up ticket with TicketNumber '$Ticket{TicketNumber}' and TicketID '$TicketID'.",
                    );

                    return ( $Ticket{TicketNumber}, $TicketID );
                }
            }
        }
    }

    return;
}

=head2 GetEmailParams()

to get all configured PostmasterX-Header email headers

    my %Header = $PostMasterObject->GetEmailParams();

=cut

sub GetEmailParams {
    my ( $Self, %Param ) = @_;

    my %GetParam;

    # parse section
    HEADER:
    for my $Param ( @{ $Self->{'PostmasterX-Header'} } ) {

        # do not scan x-otobo headers if mailbox is not marked as trusted
        next HEADER if ( !$Self->{Trusted} && $Param =~ /^x-otobo/i );

        $GetParam{$Param} = $Self->{ParserObject}->GetParam( WHAT => $Param );

        next HEADER if !$GetParam{$Param};

        $Self->{CommunicationLogObject}->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Debug',
            Key           => 'Kernel::System::PostMaster',
            Value         => "$Param: " . $GetParam{$Param},
        );
    }

    # set compat. headers
    if ( $GetParam{'Message-Id'} ) {
        $GetParam{'Message-ID'} = $GetParam{'Message-Id'};
    }
    if ( $GetParam{'Reply-To'} ) {
        $GetParam{'ReplyTo'} = $GetParam{'Reply-To'};
    }
    if (
        $GetParam{'Mailing-List'}
        || $GetParam{'Precedence'}
        || $GetParam{'X-Loop'}
        || $GetParam{'X-No-Loop'}
        || $GetParam{'X-OTOBO-Loop'}
        || (
            $GetParam{'Auto-Submitted'}
            && substr( $GetParam{'Auto-Submitted'}, 0, 5 ) eq 'auto-'
        )
        )
    {
        $GetParam{'X-OTOBO-Loop'} = 'yes';
    }
    if ( !$GetParam{'X-Sender'} ) {

        # get sender email
        my @EmailAddresses = $Self->{ParserObject}->SplitAddressLine(
            Line => $GetParam{From},
        );
        for my $Email (@EmailAddresses) {
            $GetParam{'X-Sender'} = $Self->{ParserObject}->GetEmailAddress(
                Email => $Email,
            );
        }
    }

    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    # set sender type if not given
    for my $Key (qw(X-OTOBO-SenderType X-OTOBO-FollowUp-SenderType)) {

        if ( !$GetParam{$Key} ) {
            $GetParam{$Key} = 'customer';
        }

        # check if X-OTOBO-SenderType exists, if not, set customer
        if ( !$ArticleObject->ArticleSenderTypeLookup( SenderType => $GetParam{$Key} ) ) {
            $Self->{CommunicationLogObject}->ObjectLog(
                ObjectLogType => 'Message',
                Priority      => 'Error',
                Key           => 'Kernel::System::PostMaster',
                Value         => "Can't find sender type '$GetParam{$Key}' in db, take 'customer'",
            );
            $GetParam{$Key} = 'customer';
        }
    }

    # Set article customer visibility if not given.
    for my $Key (qw(X-OTOBO-IsVisibleForCustomer X-OTOBO-FollowUp-IsVisibleForCustomer)) {
        if ( !defined $GetParam{$Key} ) {
            $GetParam{$Key} = 1;
        }
    }

    # Get body.
    $GetParam{Body} = $Self->{ParserObject}->GetMessageBody();

    # Get content type, disposition and charset.
    $GetParam{'Content-Type'}        = $Self->{ParserObject}->GetReturnContentType();
    $GetParam{'Content-Disposition'} = $Self->{ParserObject}->GetContentDisposition();
    $GetParam{Charset}               = $Self->{ParserObject}->GetReturnCharset();

    # Get attachments.
    my @Attachments = $Self->{ParserObject}->GetAttachments();
    $GetParam{Attachment} = \@Attachments;

    return \%GetParam;
}

=head2 _FilterSystemAddresses()

Filter system addresses from every pool based on To field

    my @FilteredAddresses = $PostMasterObject->_FilterSystemAddresses(
        ToString           => 'test@example.com, test2@example.com ...',
        SystemAddressPools => $SystemAddressPools,
    );

=cut

sub _FilterSystemAddresses {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ToString} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need ToString!",
        );
        return;
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $SystemAddressPools = $ConfigObject->Get('SystemAddress::Pools');
    if ( !IsHashRefWithData($SystemAddressPools) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "SystemAddress::Pools is not a hash ref!",
        );
        return;
    }

    my @FilteredAddresses;
    my @EmailAddresses = $Self->{ParserObject}->SplitAddressLine( Line => $Param{ToString} );
    my @SAPoolNames;
    EMAIL:
    for my $Email ( @EmailAddresses ) {

        next EMAIL if !$Email;

        my $Address = $Self->{ParserObject}->GetEmailAddress( Email => $Email );

        next EMAIL if !$Address;

        # use the first found address of every pool
        for my $SAPool ( keys %{ $SystemAddressPools } ) {
            if ( grep( /^$Address$/, @{ $SystemAddressPools->{$SAPool} } ) ) {
                if ( !grep( /^$SAPool$/, @SAPoolNames ) ) {
                    push(@FilteredAddresses, $Address);
                    push(@SAPoolNames, $SAPool);
                }
            }
        }
    }

    return @FilteredAddresses;
}

=head2 _RecursivePostMasterRun()

Recursive postmaster run for system address pool

    my $TicketID = $PostMasterObject->_RecursivePostMasterRun(
        GetParam          => $GetParam,
        ToString          => 'test@example.com, test2@example.com ...',
        SystemPoolAddress => 'test@example.com',
    );

=cut

sub _RecursivePostMasterRun {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(GetParam ToString SystemPoolAddress)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    my $TicketID;

    # create new communication log for every article
    my $CommunicationLogObject = $Kernel::OM->Create(
        'Kernel::System::CommunicationLog',
        ObjectParams => {
            Transport   => 'Email',
            Direction   => 'Incoming',
            AccountType => 'STDIN',
        },
    );
    $CommunicationLogObject->ObjectLogStart( ObjectLogType => 'Message' );

    # create connection details link
    my $DetailsLink   = $ConfigObject->{HttpType}. "://" . $ConfigObject->{FQDN} .
        "/otobo/index.pl?Action=AdminCommunicationLog;Subaction=Zoom;CommunicationID=$Self->{FirstCommunicationID};ObjectLogID=$Self->{FirstConnectionID}";

    $CommunicationLogObject->ObjectLog(
        ObjectLogType => 'Message',
        Priority      => 'Debug',
        Key           => 'Kernel::System::PostMaster::SystemAddressPool::OriginalMail',
        Value         => "For more details see: $DetailsLink",
    );
    $Self->{CommunicationLogObject} = $CommunicationLogObject;

    # create needed objects
    $Self->{DestQueueObject} = Kernel::System::PostMaster::DestQueue->new( %{$Self} );
    $Self->{NewTicketObject} = Kernel::System::PostMaster::NewTicket->new( %{$Self} );
    $Self->{FollowUpObject}  = Kernel::System::PostMaster::FollowUp->new( %{$Self} );
    $Self->{RejectObject}    = Kernel::System::PostMaster::Reject->new( %{$Self} );

    # set filtered address at first in To string
    $Param{GetParam}->{To} = $Param{ToString};
    $Param{GetParam}->{To} =~ s/$Param{SystemPoolAddress},\s//g;
    $Param{GetParam}->{To} = $Param{SystemPoolAddress} . ", " . $Param{GetParam}->{To};

    # set status message
    my $MessageStatus = 'Successful';

    # run post master
    my @Success = eval {
        $Self->Run( QueueID => $Param{QueueID} || 0 );
    };
    if ( !$Success[0] ) {
        $MessageStatus = 'Failed';
    }
    else {
        $TicketID = $Success[1];
    }

    # stop object / communication log
    $CommunicationLogObject->ObjectLogStop(
        ObjectLogType => 'Message',
        Status        => $MessageStatus,
    );
    $CommunicationLogObject->CommunicationStop( Status => 'Successful' );

    return $TicketID;
}

=head2 _InterdivisionalTicketLinkAdd()

Add link for system address pool tickets with new 'Interdivisional' type

    $PostMasterObject->_InterdivisionalTicketLinkAdd(
        TicketIDs => [1, 5, 8],
    );

=cut

sub _InterdivisionalTicketLinkAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{TicketIDs} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketIDs!",
        );
        return;
    }

    if ( !IsArrayRefWithData($Param{TicketIDs}) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need TicketIDs as array ref!",
        );
        return;
    }

    my @TicketIDs = @{ $Param{TicketIDs} };
    if ( scalar(@TicketIDs) < 2 ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need at least 2 ticket ids!",
        );
        return;
    }

    # link tickets
    for my $SourceTicketID ( @TicketIDs ) {
        for my $TargetTicketID ( @TicketIDs ) {

            if ( $SourceTicketID == $TargetTicketID ) {
                next;
            }

            my $Success = $Kernel::OM->Get('Kernel::System::LinkObject')->LinkAdd(
                SourceObject => 'Ticket',
                SourceKey    => $SourceTicketID,
                TargetObject => 'Ticket',
                TargetKey    => $TargetTicketID,
                Type         => 'Interdivisional',
                State        => 'Valid',
                UserID       => $Self->{PostmasterUserID},
            );
            if ( !$Success ) {

                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority      => 'error',
                    Message         => "Can't create a interdivisional link from ticket (ID: $SourceTicketID) to ticket (ID: $TargetTicketID)",
                );
            }
        }
    }

    return 1;
}

1;
