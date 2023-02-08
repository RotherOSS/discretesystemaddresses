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

use strict;
use warnings;
use utf8;

# Set up the test driver $Self when we are running as a standalone script.
use Kernel::System::UnitTest::MockTime qw(:all);
use Kernel::System::UnitTest::RegisterDriver;

use vars (qw($Self));

use Kernel::System::PostMaster;

# get needed objects
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
$ConfigObject->Set(
    Key   => 'CheckEmailAddresses',
    Value => 0,
);

my $LinkObject          = $Kernel::OM->Get('Kernel::System::LinkObject');
my $QueueObject         = $Kernel::OM->Get('Kernel::System::Queue');
my $TicketObject        = $Kernel::OM->Get('Kernel::System::Ticket');
my $ArticleObject       = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $SystemAddressObject = $Kernel::OM->Get('Kernel::System::SystemAddress');

# get helper object
$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase  => 1,
        UseTmpArticleDir => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
FixedTimeSet();

my $SPMail = <<'EOF',
Content-Type: multipart/mixed; boundary="------------pqKFDfCKOJbavE96BjxA1Yxy"

This is a multi-part message in MIME format.
--------------pqKFDfCKOJbavE96BjxA1Yxy
Content-Type: text/plain; charset=UTF-8; format=flowed
Content-Transfer-Encoding: 7bit

AddressPool Test

--------------pqKFDfCKOJbavE96BjxA1Yxy--

EOF

# add system addresses
my @SystemAddresses;
my @SystemAddressIDs;
for my $Index ( 1 .. 5 ) {

    my $SARandomID = $Helper->GetRandomID();
    my $SAName     = $SARandomID . '@example.com';
    if ( $Index < 4 ) {

        my $SystemAddressID = $SystemAddressObject->SystemAddressAdd(
            Name     => $SAName,
            Realname => 'SystemAddress' . $SARandomID,
            ValidID  => 1,
            QueueID  => 1,
            UserID   => 1,
        );
        push( @SystemAddressIDs, $SystemAddressID );
    }

    push( @SystemAddresses,  $SAName );
}

# add queues
my @QueueIDs;
my @DefaultQueues;
my %SystemAddressList = $SystemAddressObject->SystemAddressList();
%SystemAddressList    = reverse %SystemAddressList;
for my $SystemAddress ( @SystemAddresses ) {

    my $QName           = 'Queue' . $Helper->GetRandomID();
    my $SystemAddressID = $SystemAddressList{$SystemAddress};
    if ( !$SystemAddressID ) {
        $SystemAddressID = 1;
    }

    my $QueueID = $QueueObject->QueueAdd(
        Name            => $QName,
        ValidID         => 1,
        GroupID         => 1,
        SystemAddressID => $SystemAddressID,
        SalutationID    => 1,
        SignatureID     => 1,
        UserID          => 1,
    );
    push( @DefaultQueues, $QName );
    push( @QueueIDs, $QueueID );
}

# update system addresses to queue
for my $QueueID ( @QueueIDs ) {

    my %QueueData = $QueueObject->QueueGet(
        ID    => $QueueID,
    );

    my %SystemAddressData = $SystemAddressObject->SystemAddressGet(
        ID => $QueueData{SystemAddressID},
    );

    if ( %SystemAddressData ) {

        $SystemAddressData{QueueID} = $QueueID;

        $SystemAddressObject->SystemAddressUpdate(
            %SystemAddressData,
            UserID   => 1,
        );
    }
}

# set address pools
if ( ref $ConfigObject->Get('PostMaster::AddressPool') eq 'HASH' ) {

    my %AddressPoolData = (
        1 => {
            Emails => [
                $SystemAddresses[0],
                $SystemAddresses[3],
            ],
            QueueDefault => $DefaultQueues[3],
        },
        2 => {
            Emails => [
                $SystemAddresses[1],
            ],
            QueueDefault => $DefaultQueues[4],
        },
        3 => {
            Emails => [
                $SystemAddresses[2],
            ],
            QueueDefault => $DefaultQueues[2],
        },
    );

    my %AddressPools;
    for my $Count ( keys %AddressPoolData ) {

        my $APName = 'AddressPool' . $Helper->GetRandomID();
        my %Data   = %{ $ConfigObject->Get('PostMaster::AddressPool') };
        $AddressPools{ 'Custom0' . $Count }               = $Data{ 'Custom0' . $Count };
        $AddressPools{ 'Custom0' . $Count }{Name}         = $APName;
        $AddressPools{ 'Custom0' . $Count }{Emails}       = $AddressPoolData{$Count}{Emails};
        $AddressPools{ 'Custom0' . $Count }{QueueDefault} = $AddressPoolData{$Count}{QueueDefault};
    }

    $Helper->ConfigSettingChange(
        Valid => 1,
        Key   => 'PostMaster::AddressPool',
        Value => \%AddressPools,
    );
}

# filter test
my @Tests = (

    # New mail is sent to different adress pools, both linked
    {
        Name             => 'New mail is sent to different adress pools, both linked',
        From             => 'From: Customer <test@example.com>',
        To               => 'To: ' . $SystemAddresses[0] . ', ' . $SystemAddresses[1],
        Subject          => 'Subject: address pool - test v1',
        LTCount          => 1,
        LTQueueID        => $QueueIDs[1],
        LTArticleCount   => 1,
        OrigQueueID      => $QueueIDs[0],
        OrigArticleCount => 1,
        TicketCheck      => 1,
    },

    # Follow-Up mail is sent to different adress pools, both linked
    {
        Name             => 'Follow-Up mail is sent to different adress pools, both linked',
        From             => 'From: Customer <test@example.com>',
        To               => 'To: ' . $SystemAddresses[0] . ', ' . $SystemAddresses[1],
        Subject          => 'Subject: Re: [Ticket#%s] address pool - test v2',
        LTCount          => 1,
        LTQueueID        => $QueueIDs[1],
        LTArticleCount   => 2,
        OrigQueueID      => $QueueIDs[0],
        OrigArticleCount => 2,
        TicketCheck      => 2,
    },

    # Follow-Up mail is sent to different adress pools, new ticket, both linked
    {
        Name             => 'Follow-Up mail is sent to different adress pools, new ticket, both linked',
        From             => 'From: Customer <test@example.com>',
        To               => 'To: ' . $SystemAddresses[0] . ', ' . $SystemAddresses[2],
        Subject          => 'Subject: Re: [Ticket#%s] address pool - test v3',
        LTCount          => 2,
        LTQueueID        => $QueueIDs[2],
        LTArticleCount   => 1,
        OrigQueueID      => $QueueIDs[0],
        OrigArticleCount => 3,
        TicketCheck      => 2,
    },
);

# run tests
my $GetTicketID;
for my $Test (@Tests) {

    my @Return;

    my $CommunicationLogObject = $Kernel::OM->Create(
        'Kernel::System::CommunicationLog',
        ObjectParams => {
            Transport => 'Email',
            Direction => 'Incoming',
        },
    );
    $CommunicationLogObject->ObjectLogStart( ObjectLogType => 'Message' );

    # build mail
    if ($GetTicketID) {

        my $TicketNumber = $TicketObject->TicketNumberLookup(
            TicketID => $GetTicketID,
        );
        $Test->{Subject} = sprintf( $Test->{Subject}, $TicketNumber );
    }
    my $Email = "Message-ID: <" . $Helper->GetRandomID() . "\@example.com>\n"
        . $Test->{From} . "\n"
        . $Test->{To} . "\n"
        . $Test->{Subject} . "\n"
        . $SPMail
        ;

    my $PostMasterObject = Kernel::System::PostMaster->new(
        CommunicationLogObject => $CommunicationLogObject,
        Email                  => \$Email,
        Debug                  => 2,
    );

    @Return = $PostMasterObject->Run();

    $CommunicationLogObject->ObjectLogStop(
        ObjectLogType => 'Message',
        Status        => 'Successful',
    );
    $CommunicationLogObject->CommunicationStop(
        Status => 'Successful',
    );

    $Self->True(
        $Return[1] || 0,
        "$Test->{Name} - ticket of original mail exist",
    );
    $Self->Is(
        $Return[0] || 0,
        $Test->{TicketCheck},
        "$Test->{Name} - article of original mail created",
    );

    if ( !$GetTicketID ) {
        $GetTicketID = $Return[1];
    }

    my $LinkedTicket = $LinkObject->LinkList(
        Object => 'Ticket',
        Key    => $GetTicketID,
        State  => 'Valid',
        Type   => 'Interdivisional',
        UserID => 1,
    );
    my $LTCount = keys %{ $LinkedTicket->{Ticket}->{Interdivisional}->{Source} };

    $Self->Is(
        $LTCount || 0,
        $Test->{LTCount},
        "$Test->{Name} - linked ticket(s) of original mail exist",
    );

    my @TicketIDs;
    for my $LTID ( sort keys %{ $LinkedTicket->{Ticket}->{Interdivisional}->{Source} } ) {
        push( @TicketIDs, $LTID );
    }
    my $LinkedTicketID = $TicketIDs[ $LTCount - 1 ];
    push( @TicketIDs, $GetTicketID );

    my %TicketData;
    for my $TicketID (@TicketIDs) {

        my @Articles = $ArticleObject->ArticleList(
            TicketID => $TicketID,
        );
        my $ArticleCount = scalar(@Articles);

        my $TicketQueueID = $TicketObject->TicketQueueID(
            TicketID => $TicketID,
        );

        my %Data = (
            QueueID      => $TicketQueueID,
            ArticleCount => $ArticleCount,
        );
        $TicketData{$TicketID} = \%Data;
    }

    $Self->Is(
        $TicketData{$GetTicketID}{ArticleCount} || 0,
        $Test->{OrigArticleCount},
        "$Test->{Name} - article count of original ticket is correct.",
    );
    $Self->Is(
        $TicketData{$LinkedTicketID}{ArticleCount} || 0,
        $Test->{LTArticleCount},
        "$Test->{Name} - article count of linked ticket is correct.",
    );

    $Self->Is(
        $TicketData{$GetTicketID}{QueueID} || 0,
        $Test->{OrigQueueID},
        "$Test->{Name} - queue of original ticket is correct.",
    );
    $Self->Is(
        $TicketData{$LinkedTicketID}{QueueID} || 0,
        $Test->{LTQueueID},
        "$Test->{Name} - queue of linked ticket is correct.",
    );
}

# cleanup is done by RestoreDatabase.

$Self->DoneTesting();
