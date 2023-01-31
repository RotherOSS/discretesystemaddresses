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

use Kernel::System::VariableCheck qw(IsHashRefWithData);

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

# Rother OSS / DiscreteSystemAddresses

    'Kernel::System::Log',
    'Kernel::System::PostMaster::AddressPool',

# EO DiscreteSystemAddresses

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

# Rother OSS / DiscreteSystemAddresses

    $Self->{OriginCommunicationLogObject} = $Self->{CommunicationLogObject};

# EO DiscreteSystemAddresses

    $Self->{ParserObject} = Kernel::System::EmailParser->new(
        Email => $Param{Email},
    );

# Rother OSS / DiscreteSystemAddresses

    # create needed objects
    $Self->_CreateMailObjects(
        Data => $Self,
    );

    # set queue header names
    $Self->{XOTOBOQueueHeader}         = 'X-OTOBO-Queue';
    $Self->{XOTOBOFollowUpQueueHeader} = 'X-OTOBO-FollowUp-Queue';

# EO DiscreteSystemAddresses

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

    # ConfigObject section / get params
    my $GetParam = $Self->GetEmailParams();

    # check if follow up
    my ( $Tn, $TicketID ) = $Self->CheckFollowUp( GetParam => $GetParam );

    # get config objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

# Rother OSS / DiscreteSystemAddresses

    my $AddressPoolObject = $Kernel::OM->Get('Kernel::System::PostMaster::AddressPool');

    my @TicketIDsToLink;
    if ( !$Param{AddressPool} ) {

# EO DiscreteSystemAddresses

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

# Rother OSS / DiscreteSystemAddresses

        # build mail address list
        my %MailAddressList = $Self->BuildMailAddressList(
            Params            => $GetParam,
            AddressPoolFilter => 1,
        );

        if (%MailAddressList) {

            # lookup address per pool name
            my %AddressPoolNameList = $AddressPoolObject->NameList();

            if ($TicketID) {

                $Self->{XOTOBOQueueKey} = $Self->{XOTOBOFollowUpQueueHeader};

                $Param{AddressPool} = $AddressPoolObject->NameLookup(
                    TicketID => $TicketID,
                );
            }
            else {

                $Self->{XOTOBOQueueKey} = $Self->{XOTOBOQueueHeader};

                # set first address pool
                my $FirstAddress = ( sort keys %MailAddressList )[0];
                $Param{AddressPool} = $AddressPoolNameList{$FirstAddress};
            }

            # set origin X-OTOBO-Queue / X-OTOBO-FollowUp-Queue
            $Self->{XOTOBOQueue} = $GetParam->{ $Self->{XOTOBOQueueKey} };

            ADDRESS:
            for my $Address ( keys %MailAddressList ) {

                # get address pool / queue
                my $AddressPool  = $AddressPoolNameList{$Address};
                my $AddressQueue = $MailAddressList{$Address};

                if (
                    $Param{AddressPool}
                    &&
                    ( $Param{AddressPool} eq $AddressPoolNameList{$Address} )
                    )
                {

                    # set origin mail address pool and queue
                    $Self->{OrigMailQueue}       = $AddressQueue;
                    $Self->{OrigMailAddressPool} = $AddressPool;

                    next ADDRESS;
                }

                # check queue for address
                my $MailQueue = $Self->CheckAddressPoolQueue(
                    AddressPool  => $AddressPool,
                    XOTOBOQueue  => $Self->{XOTOBOQueue},
                    AddressQueue => $AddressQueue,
                );

                my $GetTicketID = $Self->RecursivePostMasterRun(
                    AddressPool      => $AddressPool,
                    MailQueue        => $MailQueue,
                    FollowUpTicketID => $TicketID,
                );
                push( @TicketIDsToLink, $GetTicketID );
            }

            # set communication log to origin
            $Self->{CommunicationLogObject} = $Self->{OriginCommunicationLogObject};
            $Self->_CreateMailObjects(
                Data => $Self,
            );

            # check queue for origin mail address
            my $MailQueue = $Self->CheckAddressPoolQueue(
                AddressPool  => $Self->{OrigMailAddressPool},
                XOTOBOQueue  => $Self->{XOTOBOQueue},
                AddressQueue => $Self->{OrigMailQueue},
            );
            $GetParam->{ $Self->{XOTOBOQueueKey} } = $MailQueue;
        }
    }
    else {

        ( $Tn, $TicketID ) = ();
        if ( $Param{FollowUpTicketID} ) {
            ( $Tn, $TicketID ) = $AddressPoolObject->FindLinkedTicket(
                TicketID    => $Param{FollowUpTicketID},
                AddressPool => $Param{AddressPool},
                UserID      => $Self->{PostmasterUserID},
            );
            if ( !$TicketID ) {
                $Self->{XOTOBOQueueKey} = $Self->{XOTOBOQueueHeader};
            }
        }

        if ( $Param{MailQueue} ) {
            $GetParam->{ $Self->{XOTOBOQueueKey} } = $Param{MailQueue};
        }
    }

# EO DiscreteSystemAddresses

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

# Rother OSS / DiscreteSystemAddresses

    # create link of type 'Interdivisional' to tickets
    push( @TicketIDsToLink, $Return[1] );
    if ( scalar(@TicketIDsToLink) > 1 ) {

        $AddressPoolObject->InterdivisionalTicketLinkAdd(
            TicketIDs => \@TicketIDsToLink,
            UserID    => $Self->{PostmasterUserID},
        );
    }

# EO DiscreteSystemAddresses

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

# Rother OSS / DiscreteSystemAddresses

=head2 RecursivePostMasterRun()

Recursive postmaster run for address pool

    my $TicketID = $PostMasterObject->RecursivePostMasterRun(
        AddressPool      => 'Pool1',   # (optional)
        MailQueue        => 'Misc',    # (optional)
        FollowUpTicketID => 4,         # (optional)
    );

Return:

    TicketID = 5

=cut

sub RecursivePostMasterRun {
    my ( $Self, %Param ) = @_;

    my $TicketID;

    # get object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

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
    my $OriginConnectionID    = $Self->{OriginCommunicationLogObject}->{Current}->{Connection};
    my $OriginCommunicationID = $Self->{OriginCommunicationLogObject}->{CommunicationID};
    if ( $OriginConnectionID && $OriginCommunicationID ) {

        my $DetailsLink = $ConfigObject->{HttpType} . "://" . $ConfigObject->{FQDN} .
            "/otobo/index.pl?Action=AdminCommunicationLog;Subaction=Zoom;CommunicationID=$OriginCommunicationID;ObjectLogID=$OriginConnectionID";

        $CommunicationLogObject->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Debug',
            Key           => 'Kernel::System::PostMaster::AddressPool::OriginalMail',
            Value         => "For more details see: $DetailsLink",
        );
    }

    # set new communication log
    $Self->{CommunicationLogObject} = $CommunicationLogObject;

    # create needed objects again
    $Self->_CreateMailObjects(
        Data => $Self,
    );

    # set status message
    my $MessageStatus = 'Successful';

    # run post master
    my @Success = eval {
        $Self->Run(
            AddressPool      => $Param{AddressPool},
            MailQueue        => $Param{MailQueue},
            FollowUpTicketID => $Param{FollowUpTicketID},
        );
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

=head2 BuildMailAddressList()

Build mail address list of To, Cc, Bcc ... as array or hash with queue

    my @MailAddressList = $PostMasterObject->BuildMailAddressList(
        Params            => $GetParam,
    );

    my %MailAddressList = $PostMasterObject->BuildMailAddressList(
        Params            => $GetParam,
        AddressPoolFilter => 1,         # (optional)
    );

Return:

    @MailAddressList = (
              'test1@example.com',
              'test2@example.com',
              'test3@example.com',
              ...
            )

    %MailAddressList = (
              'test1@example.com' => 'Misc',
              'test2@example.com' => 'Junk',
              'test3@example.com' => 'Raw',
              ...
            )

=cut

sub BuildMailAddressList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Params} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Params!",
        );
        return;
    }

    if ( !IsHashRefWithData( $Param{Params} ) ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Params as hash ref!",
        );
        return;
    }

    # get object
    my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');

    # get headers
    my %GetParam = $Param{Params}->%*;

    # check possible address headers
    my %AddressUsed;
    my @AddressList;
    HEADER:
    for my $Header (qw(To Cc Bcc)) {

        next HEADER if !$GetParam{$Header};

        my @Emails = $Self->{ParserObject}->SplitAddressLine( Line => $GetParam{$Header} );
        EMAIL:
        for my $Email (@Emails) {

            next EMAIL if !$Email;

            my $Address = $Self->{ParserObject}->GetEmailAddress( Email => $Email );

            next EMAIL if !$Address;

            if ( !$AddressUsed{$Address} ) {
                push( @AddressList, $Address );
                $AddressUsed{$Address} = 1;
            }

        }
    }

    if ( $Param{AddressPoolFilter} ) {

        # get object
        my $AddressPoolObject = $Kernel::OM->Get('Kernel::System::PostMaster::AddressPool');

        my %FilteredAddressList;
        my %AddressPoolNameList = $AddressPoolObject->NameList(
            QueueDefault => 1,
        );
        if (%AddressPoolNameList) {

            my %Queues = $QueueObject->QueueList(
                Valid => 1,
            );

            POOLNAME:
            for my $PoolName ( keys %AddressPoolNameList ) {

                my $QueueExist;
                my $MailAddress;

                # get the first found address with valid queue
                ADDRESS:
                for my $Address (@AddressList) {

                    POOLADDRESS:
                    for my $PoolAddress ( $AddressPoolNameList{$PoolName}{Emails}->@* ) {

                        if ( $Address eq $PoolAddress ) {

                            $MailAddress = $Address;

                            last POOLADDRESS;
                        }
                    }

                    if ($MailAddress) {

                        QUEUEID:
                        for my $QueueID ( keys %Queues ) {

                            my %QueueData = $QueueObject->QueueGet(
                                ID => $QueueID,
                            );

                            if ( $MailAddress eq $QueueData{Email} ) {

                                $QueueExist = $QueueData{Name};

                                last QUEUEID;
                            }
                        }

                        last ADDRESS;
                    }
                }

                # Get queue default from config
                if ( !$QueueExist ) {

                    my $QueueDefault = $AddressPoolNameList{$PoolName}{QueueDefault};
                    if ( !$MailAddress || !$QueueDefault ) {
                        next POOLNAME;
                    }
                    $QueueExist = $QueueDefault;
                }

                $FilteredAddressList{$MailAddress} = $QueueExist;
            }
        }

        return %FilteredAddressList;
    }

    return @AddressList;
}

=head2 CheckAddressPoolQueue()

Get the mail queue depends on address pool

    my $MailQueue = $PostMasterObject->CheckAddressPoolQueue(
        AddressPool  => 'Pool1',
        XOTOBOQueue  => 'Junk',   # (optional)
        AddressQueue => 'Misc',
    );

Return:

    $MailQueue = "Misc"

=cut

sub CheckAddressPoolQueue {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(AddressQueue AddressPool)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    # get object
    my $AddressPoolObject = $Kernel::OM->Get('Kernel::System::PostMaster::AddressPool');

    # Check queue in adress pool
    my $QueueExist;
    my $MailQueue = $Param{XOTOBOQueue};
    if ($MailQueue) {
        $QueueExist = $AddressPoolObject->QueueCheck(
            Queue       => $MailQueue,
            AddressPool => $Param{AddressPool},
        );
    }
    if ( !$QueueExist ) {
        $MailQueue = $Param{AddressQueue};
    }

    return $MailQueue;
}

=head2 _CreateMailObjects()

Create new mail objects (DestQueue, NewTicket, FollowUp, Reject)

    $PostMasterObject->_CreateMailObjects(
        Data => $Self,
    );

=cut

sub _CreateMailObjects {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{Data} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => "Need Data!",
        );
        return;
    }

    # create mail objects
    $Self->{DestQueueObject} = Kernel::System::PostMaster::DestQueue->new( $Param{Data}->%* );
    $Self->{NewTicketObject} = Kernel::System::PostMaster::NewTicket->new( $Param{Data}->%* );
    $Self->{FollowUpObject}  = Kernel::System::PostMaster::FollowUp->new( $Param{Data}->%* );
    $Self->{RejectObject}    = Kernel::System::PostMaster::Reject->new( $Param{Data}->%* );

    return 1;
}

# EO DiscreteSystemAddresses

1;
