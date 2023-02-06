.. toctree::
    :maxdepth: 2
    :caption: Contents

Sacrifice to Sphinx
===================

Description
===========
With this extension it is possible that (system) addresses can communicate with each other.

These are assigned to so-called address pools so that the incoming mail is divided into several tickets.

System requirements
===================

Framework
---------
OTOBO 10.1.x

Packages
--------
\-

Third-party software
--------------------
\-

Usage
=====
The agents will be able to send emails to other (system) addresses (e.g. via Cc) from within OTOBO.

If you continue to write to the same (system) address as before, a new ticket will be created in the original ticket queue and automatically linked to the moved ticket.

In addition, a new filter is added that uses the message id to recognize whether this mail already exists in OTOBO and then ignores it.

In the system configuration, there is an option to define which mail addresses form an address pool (e.g. helpdesk@..., it@... and support@... as (system) addresses of the IT-Management).

Example:

Ticket#123 in queue "IT" is linked to ticket #198 in queue "HR" and ticket #200 in queue "Students".

If an email reply "Re: [Ticket#123] My Problem" is sent to the address pools "IT-Management", "HR-Management" and "Building-Management", follow-ups would be generated in ticket #123 and ticket #198.

The ticket in the "Students" queue would remain unchanged and a new ticket would be created in the "Building" queue and linked to Ticket#123, Ticket#198 and Ticket#200.

Setup
-----
Go to "Admin -> System Configuration" and search for "AddressPool".

You have to choose one of them for example and define a pool name with their mail addresses and default queue.

|
.. image:: Screenshot_DiscreteSystemAddress_AddressPool.png
  :align: left
  :width: 500
  :alt: Screenshot showing address pool settings.
|

Configuration Reference
-----------------------

Core::Email::PostMaster::AddressPool
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PostMaster::AddressPool###Custom01
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom02
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom03
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom04
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom05
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom06
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom07
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom08
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom09
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::AddressPool###Custom10
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Defines addresses in pool to communicate with each other as entities.

PostMaster::PreFilterModule###000-MatchMessageID
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Module to check if mail with message id already exist.

Core::LinkObject
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

LinkObject::PossibleLink###2200
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Links 2 tickets with a "Interdivisional" type link.

LinkObject::Type###Interdivisional
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
This setting defines the link type 'Interdivisional'. If the source name and the target name contain the same value, the resulting link is a non-directional one. If the values are different, the resulting link is a directional link.

About
=======

Contact
-------
| Rother OSS GmbH
| Email: hello@otobo.de
| Web: https://otobo.de

Version
-------
Author: |doc-vendor| / Version: |doc-version| / Date of release: |doc-datestamp|
