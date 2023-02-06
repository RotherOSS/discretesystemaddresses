.. toctree::
    :maxdepth: 2
    :caption: Contents

Sacrifice to Sphinx
===================

Description
===========
This extension facilitates communication between system addresses within OTOBO (e.g. in cc), by linking tickets in different queues to each other and using address pools to ensure a new article is added to all relevant tickets within the system (e.g. one in the IT Queue and one in HR).

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
This extension enables OTOBO to handle emails between system addresses, and makes sure that replies are added to all relevant tickets in the system.

Address pools can be defined to detail which system addresses belong to one pool – and thus point to the same ticket/queue (e.g. helpdesk@..., it@... and support@... as system addresses of the IT Department).

Example:

When an OTOBO Agent from IT writes an email to a customer and puts HR in cc, two tickets are created in the system – Ticket#123 in the queue "IT" and a linked ticket #198 in queue "HR".

If an email reply "Re: [Ticket#123] My Problem" is now sent from an "HR" address to addresses in the address pools "IT-Management" and "Building-Management", follow-ups are generated in ticket #123 and #198.

Moreover, a new ticket is created in the "Building" queue, which is linked to Ticket#123 and Ticket#198.

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

Core::Email::PostMaster
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PostMaster::PreFilterModule###000-MatchMessageID
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Module to check if mail with message id already exist.

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
