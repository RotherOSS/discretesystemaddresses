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

DiscreteAddresses Test

--------------pqKFDfCKOJbavE96BjxA1Yxy--

EOF

# add system addresses
my @SystemAddressIDs;
my @SystemAddresses;
for (0 .. 2) {

    my $SARandomID = $Helper->GetRandomID();
    my $SAName     = $SARandomID . '@example.com';
    my $SystemAddressID = $SystemAddressObject->SystemAddressAdd(
        Name     => $SAName,
        Realname => 'SystemAddress' . $SARandomID,
        ValidID  => 1,
        QueueID  => 1,
        UserID   => 1,
    );
    push (@SystemAddressIDs, $SystemAddressID);
    push (@SystemAddresses, $SAName);
}

# add queues
my $QueueDefault;
my @QueueIDs;
for my $Index (0 .. 2) {

    my $QName = 'Queue' .  $Helper->GetRandomID();
    my $QueueID = $QueueObject->QueueAdd(
        Name                => $QName,
        ValidID             => 1,
        GroupID             => 1,
        SystemAddressID     => $SystemAddressIDs[$Index],
        SalutationID        => 1,
        SignatureID         => 1,
        UserID              => 1,
    );
    $QueueDefault = $QName;
    push(@QueueIDs, $QueueID);
}

# set address pools
if ( ref $ConfigObject->Get('PostMaster::AddressPool') eq 'HASH' ) {

    my %AddressPool;
    for my $Index (1 .. 2) {

        my $APName = 'AddressPool' . $Helper->GetRandomID();
        my %Data = %{ $ConfigObject->Get('PostMaster::AddressPool') };
        $AddressPool{'Custom' . $Index} = $Data{'Custom' . $Index};
        $AddressPool{'Custom' . $Index}{Name} = $APName;
        $AddressPool{'Custom' . $Index}{QueueDefault} = $QueueDefault;
        $AddressPool{'Custom' . $Index}{Emails} = [ $SystemAddresses[$Index -1 ] ];
    }

    $Helper->ConfigSettingChange(
        Valid => 1,
        Key   => 'PostMaster::AddressPool',
        Value => \%AddressPool,
    );
}

# filter test
my @Tests = (
    # Mail is sent to different adress pools, no follow-up
    {
        Name        => 'Mail is sent to different adress pools, no follow-up',
        From        => 'From: Customer <test@example-' . $Helper->GetRandomID() . '.com>',
        To          => 'To: ' . $SystemAddresses[0] . ', ' . $SystemAddresses[1],
        Subject     => 'Subject: discrete addresses - test v1',
        LTCount     => 1,
        LTQueueID   => $QueueIDs[1],
        OrigQueueID => $QueueIDs[0],
        TicketCheck => 1,
    },
);

# run tests
for my $Test ( @Tests ) {
    my @Return;
    {
        my $CommunicationLogObject = $Kernel::OM->Create(
            'Kernel::System::CommunicationLog',
            ObjectParams => {
                Transport => 'Email',
                Direction => 'Incoming',
            },
        );
        $CommunicationLogObject->ObjectLogStart( ObjectLogType => 'Message' );

        # build mail
        my $Email = $Test->{From} . "\n" . $Test->{To} . "\n" . $Test->{Subject} . "\n" . $SPMail;

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
    }
    $Self->True(
        $Return[1] || 0,
        "$Test->{Name} - ticket of original mail exist",
    );
    $Self->Is(
        $Return[0] || 0,
        $Test->{TicketCheck},
        "$Test->{Name} - article of original mail created",
    );

    my $NewTicketID  = $Return[1];
    my $LinkedTicket = $LinkObject->LinkList(
        Object => 'Ticket',
        Key    => $NewTicketID,
        State  => 'Valid',
        Type   => 'Interdivisional',
        UserID => 1,
    );
    my $LTCount = keys %{ $LinkedTicket };

    $Self->Is(
        $LTCount || 0,
        $Test->{LTCount},
        "$Test->{Name} - linked ticket of original mail exist",
    );

    my ($LinkedTicketID) = keys %{ $LinkedTicket->{Ticket}->{Interdivisional}->{Source} };
    my @TicketIDs = (
        $NewTicketID,
        $LinkedTicketID,
    );

    my @QueueIDs;
    for my $TicketID ( @TicketIDs ) {

        my $QueueID = $TicketObject->TicketQueueID(
            TicketID => $TicketID,
        );
        push(@QueueIDs, $QueueID);
    }
    @QueueIDs = sort @QueueIDs;

    $Self->Is(
        $QueueIDs[0] || 0,
        $Test->{OrigQueueID},
        "$Test->{Name} - queue of original ticket correctly.",
    );

    $Self->Is(
        $QueueIDs[1] || 0,
        $Test->{LTQueueID},
        "$Test->{Name} - queue of linked ticket correctly.",
    );
}

# cleanup is done by RestoreDatabase.

$Self->DoneTesting();
