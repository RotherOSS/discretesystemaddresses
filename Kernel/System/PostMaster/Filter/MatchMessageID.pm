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

package Kernel::System::PostMaster::Filter::MatchMessageID;

use strict;
use warnings;

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

    return if !$MessageID;

    $Self->_AddCommunicationLog(
        Message => sprintf(
            'Searching for article with message id "%s".',
            $MessageID,
        ),
    );

    my %Article = $Self->{ArticleBackendObject}->ArticleGetByMessageID(
        MessageID => $MessageID,
    );

    if (%Article) {

        $Self->_AddCommunicationLog(
            Message => sprintf(
                'Article with message id "%s" already exist, ignore it.',
                $MessageID,
            ),
        );

        $Param{GetParam}->{'X-OTOBO-Ignore'} = 'yes';
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
