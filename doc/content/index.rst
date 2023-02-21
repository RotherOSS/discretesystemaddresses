.. toctree::
    :maxdepth: 2
    :caption: Contents

Sacrifice to Sphinx
===================

Description
===========
This extension facilitates communication between system addresses within OTOBO (e.g. in cc), by defining address pools which are treated as separate entities in the system. Mails sent to multiple pools create an article in every pool, associated tickets are linked and will be used to assign FollowUps.

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

Details
-------
Address pools can be defined to define which email addresses and implicitely queues belong to one entity, via PostMaster::AddressPool###Poolxy. Within those entities destination queues are determined as usual. Individual default queues can be provided. X-OTOBO-Queue and X-OTOBO-FollowUpQueue are only respected for articles created in the respective pool.

Example:

When an email to an IT and a sales department, both set up as different entities, is received, two tickets are created in the system – Ticket#123 in the queue "IT::Incidents" and a linked Ticket#124 in the queue "Inquiries".
Sales can now answer the customer "Re: [Ticket#124] My Problem; Please discuss this with the IT directly.", and just put it@ourticketsystem into the cc. This will create the respective article in Ticket#123, and if the customer now only sends his answer to it@ourticketsystem, even if it is an answer to the last mail and uses the subject "Re: [Ticket#124] My Problem - specification", the FollowUp will be created in Ticket#123 (email addresses take precedence).

As an important note: Since single emails may now create multiple articles (necessary for email aliases), single emails (identified by the messageid) cannot be read in multiple times. For almost all cases this should not make any difference, but it means that even with this OTOBO extension it won't be possible to bounce an email from one address pool to another.

Configuration Reference
-----------------------

Core::Email::PostMaster
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PostMaster::PreFilterModule###000-SkipViaMessageID
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Module to check if an article with the corresponding message id already exists in the system. (E.g. if the mail was received and processed through a different email inbox.)

Core::Email::PostMaster::AddressPool
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PostMaster::AddressPool###Pool01
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
All email addresses which make up one pool. Queues are assigned implicitely. A default queue can be provided.

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
