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

package Kernel::System::PostMaster::Filter::SkipViaMessageID;

use strict;
use warnings;

use Mail::Address;

our @ObjectDependencies = (
    'Kernel::System::Log',
    'Kernel::System::Ticket::Article',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get parser object
    $Self->{ParserObject} = $Param{ParserObject} || die "Got no ParserObject!";

    # Get communication log object.
    $Self->{CommunicationLogObject} = $Param{CommunicationLogObject} || die "Got no CommunicationLogObject!";

    # Get Article backend object.
    $Self->{ArticleBackendObject} =
        $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel( ChannelName => 'Email' );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    $Self->_AddCommunicationLog( Message => 'Searching for header Message-ID.' );

    my $MessageID = $Param{GetParam}->{'Message-ID'};

    return 1 if !$MessageID;

    $Self->_AddCommunicationLog(
        Message => sprintf(
            'Searching for article with message id "%s".',
            $MessageID,
        ),
    );

    my %Article = $Self->{ArticleBackendObject}->ArticleGetByMessageID(
        MessageID => $MessageID,
    );

    return 1 if !%Article;

    if ( !$Article{AmbiguousTicketIDs} ) {
        my ( $SenderEmail ) = Mail::Address->parse( $Article{From} );

        my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
            Address => $SenderEmail->address(),
        );

        # if we are reading a message sent via our OTOBO itself for the first time
        if ( $IsLocal ) {
            $Self->_AddCommunicationLog(
                Message => sprintf(
                    'Email with message id "%s" was sent as new article from a local address.',
                    $MessageID,
                ),
            );

            return 1;
        }
    }

    if ( !$Param{JobConfig} || !$Param{JobConfig}{AllowMultiParse} ) {
        $Self->_AddCommunicationLog(
            Message => sprintf(
                'Article with message id "%s" already exists, setting X-OTOBO-Ignore.',
                $MessageID,
            ),
        );
        $Param{GetParam}{'X-OTOBO-Ignore'} = 'yes';

        return 1;
    }

    my $MultiParse = $Param{JobConfig}{AllowMultiParse}{Always} ? 1 : 0;

    if ( !$MultiParse && $Param{JobConfig}{AllowMultiParse}{MailAccountQueue} && $Param{QueueID} ) {
        $Self->_AddCommunicationLog(
            Message => sprintf(
                'Article with message id "%s" already exists, parse again as explicit QueueID is provided.',
                $MessageID,
            ),
        );

        $MultiParse = 1;
    }

    if ( !$MultiParse && $Param{JobConfig}{AllowMultiParse}{BouncedEmail} && $Param{GetParam}{'Resent-To'} ) {
        $Self->_AddCommunicationLog(
            Message => sprintf(
                'Article with message id "%s" already exists, parse again as email was bounced.',
                $MessageID,
            ),
        );

        $MultiParse = 1;
    }

    if ( !$MultiParse ) {
        $Self->_AddCommunicationLog(
            Message => sprintf(
                'Article with message id "%s" already exists, setting X-OTOBO-Ignore.',
                $MessageID,
            ),
        );
        $Param{GetParam}{'X-OTOBO-Ignore'} = 'yes';

        return 1;
    }

    my $AddressPoolObject = $Kernel::OM->Get('Kernel::System::PostMaster::AddressPool');
    TICKETID:
    for my $TicketID ( $Article{AmbiguousTicketIDs}->@* ) {
        my $Pool = $AddressPoolObject->PoolLookup(
            TicketID => $TicketID,
        );

        next TICKETID if !$Pool;

        $Param{GetParam}{IgnoreAddressPools}{ $Pool } = 1;
    }

    return 1;
}

sub _AddCommunicationLog {
    my ( $Self, %Param ) = @_;

    $Self->{CommunicationLogObject}->ObjectLog(
        ObjectLogType => 'Message',
        Priority      => $Param{Priority} || 'Debug',
        Key           => ref($Self),
        Value         => $Param{Message},
    );

    return;
}

1;
