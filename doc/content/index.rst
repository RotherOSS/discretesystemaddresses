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
OTOBO 11.0.x

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
Address pools can be defined to define which email addresses and implicitely queues belong to one entity, via PostMaster::AddressPool###Poolxy. Within those entities destination queues are determined as usual. Individual default queues can be provided. Optional QueueID from Mailaccount (if dispatching via Queue is active) X-OTOBO-Queue and X-OTOBO-FollowUpQueue are only respected for articles created in the respective pool.

Example:

When an email to an IT and a sales department, both set up as different entities, is received, two tickets are created in the system – Ticket#123 in the queue "IT::Incidents" and a linked Ticket#124 in the queue "Inquiries".
Sales can now answer the customer "Re: [Ticket#124] Not my Problem; Please discuss this with the IT directly.", and just put it@ourticketsystem into the cc. This will create the respective article in Ticket#123, and if the customer now only sends his answer to it@ourticketsystem, even if it is an answer to the last mail and uses the subject "Re: [Ticket#124] My Problem - specification", the FollowUp will be created in Ticket#123 (email addresses take precedence).

**Warning:** Be careful with setting up automatic replies - this package introduces additional ways to create loops, especially when replies are also sent on FollowUps.

Short ruleset for deciding if an where articles are created:

#. If no Pool is addressed in any parsed email header and optional Mailaccount-queue is not associated to any pool, treat the mail as if the package was not installed.
#. As soon as at least one pool is addressed, create exactly one article for each addressed pool, and no more.
#. Prio is 1. X-OTOBO-Queue-Header (if in respective pool), 2. Mailaccount-queue (if in respective pool), 3. queue associated to the pool via email address, 4. default queue of pool, 5. PostMaster default queue
#. An email with the same message-id is only parsed more than once if either, it is sent by the system and only present once, or the mail was bounced or dispatching via Queue is active in the receiving mail account. This can be configured also with the SkipViaMessageID PreFilterModule. In any case there will never be more than one article created per message-id per pool.
#. FollowUp check, assoicates tickets in other pools linked via the interdivisional link type, and should do "the right thing", regardless of which of the linked tickets is found. Rule 2 overrides follow up ticket association.

Configuration Reference
-----------------------

AutoloadPerlPackages###1000-TicketSubjectCleanInterdivisionalTicketNumbers
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Remove ticket numbers of all interdivisionally linked tickets when subject is cleaned.

Core::Email::PostMaster
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

PostMaster::AddressPool::EmailHeaders
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Email headers used for address-pool assignment. Secondary headers are not evaluated if pools could be assigned via the primary headers.


PostMaster::PreFilterModule###000-SkipViaMessageID
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Module to check if an article with the corresponding message id already exists in the system. (E.g. if the mail was received and processed through a different email inbox.) Multiple parsing can be allowed. Pools which already contain an article with the respective message id will still be ignored. Options are "Always", "BouncedEmail" (multiple parsing will only be done for Emails with "Resent-To"-header, e.g. PoolA bounced a mail to PoolB) and "MailAccountQueue" (if dispatching via queue is enabled for a mail account, an email can be moved to the respective inbox, to be evaluated again).

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
