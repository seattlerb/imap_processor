= imap_processor

* http://seattlerb.rubyforge.org/imap_processor

== DESCRIPTION:

IMAPProcessor is a client for processing messages on an IMAP server.  It
provides some basic mechanisms for connecting to an IMAP server, determining
capabilities and handling messages.

IMAPProcessor ships with the executables imap_keywords which can query an IMAP
server for keywords set on messages in mailboxes, imap_idle which can show new
messages in a mailbox and imap_archive which will archive old messages to a
new mailbox.

== FEATURES/PROBLEMS:

* Connection toolkit
* Executable toolkit
* Only known to work with SASL/PLAIN authentication

== SYNOPSIS:

See IMAPProcessor and IMAPProcessor::Keywords for details

== REQUIREMENTS:

* IMAP server

== INSTALL:

* gem install imap_processor

== LICENSE:

(The MIT License)

Copyright (c) 2009 Eric Hodel

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
