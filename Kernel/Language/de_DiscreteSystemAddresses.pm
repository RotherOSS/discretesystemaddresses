# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
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

package Kernel::Language::de_DiscreteSystemAddresses;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # SysConfig
    $Self->{Translation}->{'All email addresses which make up one pool. Queues are assigned implicitely. A default queue can be provided.'} =
        '';
    $Self->{Translation}->{'Email headers used for address-pool assignment. Secondary headers are not evaluated if pools could be assigned via the primary headers.'} =
        '';
    $Self->{Translation}->{'Interdivisional'} = 'Bereichsübergreifend';
    $Self->{Translation}->{'Links 2 tickets with a "Interdivisional" type link.'} = '';
    $Self->{Translation}->{'Module to check if an article with the corresponding message id already exists in the system. (E.g. if the mail was received and processed through a different email inbox.) Multiple parsing can be allowed. Pools which already contain an article with the respective message id will still be ignored. Options are "Always", "BouncedEmail" (multiple parsing will only be done for Emails with "Resent-To"-header, e.g. PoolA bounced a mail to PoolB) and "MailAccountQueue" (if dispatching via queue is enabled for a mail account, an email can be moved to the respective inbox, to be evaluated again).'} =
        '';
    $Self->{Translation}->{'Remove ticket numbers of all interdivisionally linked tickets when subject is cleaned.'} =
        '';
    $Self->{Translation}->{'This setting defines the link type \'Interdivisional\'. If the source name and the target name contain the same value, the resulting link is a non-directional one. If the values are different, the resulting link is a directional link.'} =
        '';


    push @{ $Self->{JavaScriptStrings} // [] }, (
    );

}

1;
