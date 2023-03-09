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

# Pool |        Address | Queue
#   P1   a1p1@otobo.org      q1
#   P1   a2p1@otobo.org
#   P2   a1p2@otobo.org      q2
#   P2   a2p2@otobo.org      q5
#   P3   a1p3@otobo.org      q3
#   P3   a2p3@otobo.org
#          ax@otobo.org

# Pool | DefQueue
#   P1         q4
#   P2         q5
#   P3         q3
#              q5

# add system addresses
my %SystemAddressIDs;
for my $Address ( qw/a1P1@otobo.org a1p2@otoBo.org a1p3@otobo.org a2p2@otobo.org unused@otobo.org/ ) {
    my $SystemAddressID = $SystemAddressObject->SystemAddressAdd(
        Name     => $Address,
        Realname => 'APTest',
        ValidID  => 1,
        QueueID  => 1,
        UserID   => 1,
    );

    $SystemAddressIDs{ $Address } = $SystemAddressID;
}

my %QueueAddresses = (
    q1 => 'a1P1@otobo.org',
    q2 => 'a1p2@otoBo.org',
    q3 => 'a1p3@otobo.org',
    q4 => 'unused@otobo.org',
    q5 => 'a2p2@otobo.org',
);

# add queues
my %QueueIDs;
for my $Queue ( keys %QueueAddresses ) {
    my $QueueID = $QueueObject->QueueAdd(
        Name            => $Queue,
        ValidID         => 1,
        GroupID         => 1,
        SystemAddressID => $SystemAddressIDs{ $QueueAddresses{ $Queue } },
        SalutationID    => 1,
        SignatureID     => 1,
        UserID          => 1,
    );

    $QueueIDs{ $Queue } = $QueueID;

    # update system address
    my %SystemAddressData = $SystemAddressObject->SystemAddressGet(
        ID => $SystemAddressIDs{ $QueueAddresses{ $Queue } },
    );

    $SystemAddressData{QueueID} = $QueueID;

    $SystemAddressObject->SystemAddressUpdate(
        %SystemAddressData,
        UserID   => 1,
    );
}

# set address pools
{
    my %AddressPoolData = (
        Pool01 => {
            Name   => 'P1',
            Emails => [
                'a1p1@otobo.org',
                'a2p1@otobo.org',
            ],
            DefaultQueue => 'q4',
        },
        Pool02 => {
            Name   => 'P2',
            Emails => [
                'a1p2@otobo.org',
                'a2p2@otobo.org',
            ],
            DefaultQueue => 'q5',
        },
        Pool03 => {
            Name   => 'P3',
            Emails => [
                'A1p3@otobo.org',
                'A2p3@otobo.org',
            ],
            DefaultQueue => 'q3',
        },
    );

    $Helper->ConfigSettingChange(
        Valid => 1,
        Key   => 'PostMaster::AddressPool',
        Value => \%AddressPoolData,
    );
}

# Start tests

# Test: Ticket#x in q1 (ignore defqueue of a2p1), Ticket#y in q2, nothing in q5
my $Email = GenerateEmail(
    To        => 'a2p1@otobo.orG, a1p1@otobo.orG, a1p2@otobo.orG, not@ours.com',
    Subject   => 'Initial',
    MessageID => '<20230214002814.AddressPools1@test>',
);

my ( $Return, @TicketIDs ) = ReadEmail( $Email, 1 );

# two tickets should be created...
$Self->Is(
    scalar @TicketIDs,
    2,
    "Mail1 - create two tickets.",
);

my @TestTickets;
for my $ID ( @TicketIDs ) {
    push @TestTickets, {
        $TicketObject->TicketGet( TicketID => $ID )
    };
}

# ticket 1 should be in q1
$Self->Is(
    $TestTickets[0]{Queue} // '',
    'q1',
    "Mail1 - Ticket1 is in q1.",
);

# ticket 2 should be in q2
$Self->Is(
    $TestTickets[1]{Queue} // '',
    'q2',
    "Mail1 - Ticket2 is in q2.",
);

my @Articles = $ArticleObject->ArticleList(
    TicketID => $TestTickets[0]{TicketID},
);

# ticket 1 should have exactly 1 article
$Self->Is(
    scalar @Articles,
    1,
    "Mail1 - Ticket1 has 1 article.",
);

# Test: Ticket1#Number -> FollowUp in q2, New in q3 (defqueue)
my $NewSubject = $TicketObject->TicketSubjectBuild(
    TicketNumber => $TestTickets[0]{TicketNumber},
    Subject      => 'Initial',
    Action       => 'Reply',
);

$Email = GenerateEmail(
    To        => 'a1p2@oTobo.org, a2p3@otobo.orG',
    Subject   => $NewSubject,
    MessageID => '<20230214002814.AddressPools2@test>',
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# two articles should be created...
$Self->Is(
    scalar @TicketIDs,
    2,
    "Mail2 - create two articles.",
);

# ticket 1 should be ticket 2 of last email
$Self->Is(
    $TicketIDs[0],
    $TestTickets[1]{TicketID},
    "Mail2 - Ticket1 is old Ticket2.",
);

push @TestTickets, {
    $TicketObject->TicketGet( TicketID => $TicketIDs[1] ),
};

# ticket 3 should be in q3
$Self->Is(
    $TestTickets[2]{Queue} // '',
    'q3',
    "Mail2 - Ticket2 is in q3.",
);

# keep for later
my $Email2 = $Email;

# Test: Re Ticket3#Number creates article in Ticket1
$NewSubject = $TicketObject->TicketSubjectBuild(
    TicketNumber => $TestTickets[2]{TicketNumber},
    Subject      => 'Initial',
    Action       => 'Reply',
);

$Email = GenerateEmail(
    To        => 'a1p1@otobo.org',
    Subject   => $NewSubject,
    MessageID => '<20230214002814.AddressPools3@test>',
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# ticket 1 should be ticket 1 of the first email
$Self->Is(
    $TicketIDs[0],
    $TestTickets[0]{TicketID},
    "Mail3 - Ticket1 is old Ticket1.",
);

@Articles = $ArticleObject->ArticleList(
    TicketID => $TestTickets[0]{TicketID},
);

# ticket 1 should have 2 articles
$Self->Is(
    scalar @Articles,
    2,
    "Mail3 - Ticket1 has 2 articles.",
);

# Test: standard case
$Email = GenerateEmail(
    To        => 'ax@otobo.org',
    Subject   => 'Kein Pool',
    MessageID => '<20230214002814.AddressPools4@test>',
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# one ticket should be created
$Self->Is(
    scalar @TicketIDs,
    1,
    "Mail4 - a ticket is created.",
);

my %Ticket = $TicketObject->TicketGet( TicketID => $TicketIDs[0] );

# ticket is in default queue
$Self->Is(
    $Ticket{Queue},
    $ConfigObject->Get('PostmasterDefaultQueue'),
    "Mail4 - ticket is created in def queue.",
);

# Test: ignore already received mails
( $Return, @TicketIDs ) = ReadEmail( $Email2 );

# no ticket should be created
$Self->Is(
    $Return,
    5,
    "Mail5 - mail ignored.",
);

# no ticket should be created
$Self->Is(
    scalar @TicketIDs,
    0,
    "Mail5 - no article.",
);

# Test: Re Ticket3#Number creates article in Ticket1
$NewSubject = $TicketObject->TicketSubjectBuild(
    TicketNumber => $TestTickets[2]{TicketNumber},
    Subject      => 'Initial',
    Action       => 'Reply',
);

$Email = GenerateEmail(
    To        => 'a1p1@otobo.org, a1p2@otobo.org',
    Subject   => $NewSubject,
    MessageID => '<20230214002814.AddressPools6@test>',
    XHeader   => "\nX-OTOBO-FollowUp-Queue: q5",
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# ticket 1 should be ticket 1 of the first email
$Self->Is(
    $TicketIDs[0],
    $TestTickets[0]{TicketID},
    "Mail6 - Ticket1 is old Ticket1.",
);

# ticket 2 should be ticket 2 of the first email
$Self->Is(
    $TicketIDs[1],
    $TestTickets[1]{TicketID},
    "Mail6 - Ticket2 is old Ticket2.",
);

for my $i ( 0, 1 ) {
    $TestTickets[$i] = { $TicketObject->TicketGet( TicketID => $TicketIDs[$i] ) };
}

# ticketqueue 1 should still be q1
$Self->Is(
    $TestTickets[0]->{Queue},
    'q1',
    "Mail6 - Queue of Ticket 1 is q1.",
);

# ticketqueue 2 should now be q5 of the X-OTOBO-FollowUp-Queue header
$Self->Is(
    $TestTickets[1]->{Queue},
    'q5',
    "Mail6 - Queue of Ticket 2 is q5.",
);

# Test: Do not ignore mails sent from the system
my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel(ChannelName => 'Email');
$ArticleBackendObject->ArticleCreate(
        TicketID             => $TestTickets[0]{TicketID},
        SenderType           => 'agent',
        IsVisibleForCustomer => 1,
        UserID               => 1,
        From           => '"P1" <a1p1@otobo.org>',
        To             => '"P2" <a1p2@otobo.org>',
        Subject        => 'some short description',
        Body           => 'the message text',
        MessageID      => '<20230214002814.AddressPools7@test>',
        ContentType    => 'text/plain; charset=ISO-8859-15',
        HistoryType    => 'AddNote',
        HistoryComment => 'Some free text!',
        NoAgentNotify  => 1,
);

$NewSubject = $TicketObject->TicketSubjectBuild(
    TicketNumber => $TestTickets[0]{TicketNumber},
    Subject      => 'some short description',
    Action       => 'Reply',
);

$Email = GenerateEmail(
    To        => 'a1p2@otobo.org',
    Subject   => $NewSubject,
    MessageID => '<20230214002814.AddressPools7@test>',
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# one article should be created
$Self->Is(
    scalar @TicketIDs,
    1,
    "Mail7 - one article.",
);

# ticket 1 should be ticket 2 of the first email
$Self->Is(
    $TicketIDs[0],
    $TestTickets[1]{TicketID},
    "Mail7 - Ticket1 is old Ticket2.",
);

( $Return, @TicketIDs ) = ReadEmail( $Email );

# on second round though, mail should be ignored
$Self->Is(
    $Return,
    5,
    "Mail7.5 - mail ignored.",
);

# no ticket should be created
$Self->Is(
    scalar @TicketIDs,
    0,
    "Mail7.5 - no article.",
);

# Test: Dispatching via Queue
$Email = GenerateEmail(
    To        => 'a1p1@otobo.org',
    Subject   => 'New',
    MessageID => '<20230214002814.AddressPools8@test>',
);

( $Return, @TicketIDs ) = ReadEmail( $Email, $QueueIDs{q2} );

# two tickets should be created...
$Self->Is(
    scalar @TicketIDs,
    2,
    "Mail8 - create two tickets.",
);

my @Test8Tickets;
for my $ID ( @TicketIDs ) {
    push @Test8Tickets, {
        $TicketObject->TicketGet( TicketID => $ID )
    };
}

# ticket 1 should be in q2
$Self->Is(
    $Test8Tickets[0]{Queue} // '',
    'q2',
    "Mail8 - Ticket1 is in q2.",
);

# ticket 2 should be in q1
$Self->Is(
    $Test8Tickets[1]{Queue} // '',
    'q1',
    "Mail8 - Ticket2 is in q1.",
);

# Test: Dispatching via Queue second round
( $Return, @TicketIDs ) = ReadEmail( $Email, $QueueIDs{q3} );

# one additional ticket should be created...
$Self->Is(
    scalar @TicketIDs,
    1,
    "Mail8.5 - one ticket.",
);

my ( $LinkedTicketNumber, $LinkedTicketID ) = $Kernel::OM->Get('Kernel::System::PostMaster::AddressPool')->FindLinkedTicket(
    TicketID    => $TicketIDs[0],
    AddressPool => 'Pool02',
    UserID      => 1,
);

# ...and be linked to the former ones
$Self->Is(
    $LinkedTicketID,
    $Test8Tickets[0]{TicketID},
    "Mail8.5 - correctly linked.",
);

# Test: Dispatching via Queue third time unlucky
( $Return, @TicketIDs ) = ReadEmail( $Email, $QueueIDs{q3} );

# on third round though, mail should be ignored, as all pools are full
$Self->Is(
    $Return,
    5,
    "Mail8.6 - mail ignored.",
);

# no ticket should be created
$Self->Is(
    scalar @TicketIDs,
    0,
    "Mail8.6 - no article.",
);

# cleanup is done by RestoreDatabase.
$Self->DoneTesting();


sub GenerateEmail {
    my %Param = @_;

    $Param{XHeader} //= '';

    return <<END
From skywalker\@otobo.org Fri Dec 21 23:59:24 2001
Return-Path: <skywalker\@otobo.org>
Received: (from skywalker\@localhost)
    by avro.de (8.11.3/8.11.3/SuSE Linux 8.11.1-0.5) id f3MMSE303694
    for martin\@localhost; Fri, 21 Dec 2001 23:59:24 +0200
Date: Fri, 21 Dec 2001 23:59:24 +0200
From: Skywalker Attachment <skywalker\@otobo.org>
To: $Param{To}
Subject: $Param{Subject}
Message-ID: $Param{MessageID}
Mime-Version: 1.0
Content-Type: text/plain; charset=us-ascii
Content-Disposition: inline$Param{XHeader}
X-Operating-System: Linux 2.4.10-4GB i686
X-Uptime: 12:23am  up  5:19,  6 users,  load average: 0.11, 0.13, 0.18
Content-Length: 139
Lines: 11

This is the first test.

Adios ...

  Little "Skywalker"

--
System Tester I - <skywalker\@otobo.org>
--
Old programmers never die. They just branch to a new address.
END
}

sub ReadEmail {
    # start a new incoming communication
    my $CommunicationLogObject = $Kernel::OM->Create(
        'Kernel::System::CommunicationLog',
        ObjectParams => {
            Transport   => 'Email',
            Direction   => 'Incoming',
            AccountType => 'STDIN',
        },
    );

    # start object log for the incoming connection
    $CommunicationLogObject->ObjectLogStart( ObjectLogType => 'Connection' );

    $CommunicationLogObject->ObjectLog(
        ObjectLogType => 'Connection',
        Priority      => 'Debug',
        Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
        Value         => 'Read Email from AddressPoolTest.',
    );

    # start object log for the email processing
    $CommunicationLogObject->ObjectLogStart( ObjectLogType => 'Message' );

    # remember the return code to stop the communictaion later with a proper status
    my $PostMasterReturnCode = 0;
    my @Return;

    # Wrap the main part of the script in an "eval" block so that any
    # unexpected (but probably transient) fatal errors (such as the
    # database being unavailable) can be trapped without causing a
    # bounce
    eval {

        $CommunicationLogObject->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Debug',
            Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
            Value         => 'Processing email with PostMaster module.',
        );

        my $PostMasterObject = $Kernel::OM->Create(
            'Kernel::System::PostMaster',
            ObjectParams => {
                CommunicationLogObject => $CommunicationLogObject,
                Email                  => [ split("\n", $_[0]) ],
                Trusted                => 1,
            },
        );

        @Return = $PostMasterObject->Run( QueueID => $_[1] );

        if ( !$Return[0] ) {

            $CommunicationLogObject->ObjectLog(
                ObjectLogType => 'Message',
                Priority      => 'Error',
                Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
                Value         => 'PostMaster module exited with errors, could not process email. Please refer to the log!',
            );
            $CommunicationLogObject->CommunicationStop( Status => 'Failed' );

            die "Could not process email. Please refer to the log!\n";
        }

        my $Dump = $Kernel::OM->Get('Kernel::System::Main')->Dump( \@Return );
        $CommunicationLogObject->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Debug',
            Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
            Value         => "Email processing with PostMaster module completed, return data: $Dump",
        );

        $PostMasterReturnCode = $Return[0];
    };

    if ($@) {

        # An unexpected problem occurred (for example, the database was
        # unavailable). Return an EX_TEMPFAIL error to cause the mail
        # program to requeue the message instead of immediately bouncing
        # it; see sysexits.h. Most mail programs will retry an
        # EX_TEMPFAIL delivery for about four days, then bounce the
        # message.)
        my $Message = $@;

        $CommunicationLogObject->ObjectLog(
            ObjectLogType => 'Message',
            Priority      => 'Error',
            Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
            Value         => "An unexpected error occurred, message: $Message",
        );

        $CommunicationLogObject->ObjectLogStop(
            ObjectLogType => 'Message',
            Status        => 'Failed',
        );
        $CommunicationLogObject->ObjectLogStop(
            ObjectLogType => 'Connection',
            Status        => 'Failed',
        );
        $CommunicationLogObject->CommunicationStop( Status => 'Failed' );

        return;
    }

    $CommunicationLogObject->ObjectLog(
        ObjectLogType => 'Connection',
        Priority      => 'Debug',
        Key           => 'Kernel::System::Console::Command::Maint::PostMaster::Read',
        Value         => 'Closing connection from STDIN.',
    );

    $CommunicationLogObject->ObjectLogStop(
        ObjectLogType => 'Message',
        Status        => 'Successful',
    );
    $CommunicationLogObject->ObjectLogStop(
        ObjectLogType => 'Connection',
        Status        => 'Successful',
    );

    my %ReturnCodeMap = (
        0 => 'Failed',        # error (also false)
        1 => 'Successful',    # new ticket created
        2 => 'Successful',    # follow up / open/reopen
        3 => 'Successful',    # follow up / close -> new ticket
        4 => 'Failed',        # follow up / close -> reject
        5 => 'Successful',    # ignored (because of X-OTOBO-Ignore header)
    );

    $CommunicationLogObject->CommunicationStop(
        Status => $ReturnCodeMap{$PostMasterReturnCode} // 'Failed',
    );

    return @Return;
}

