require "time"

class Time                           # :nodoc:
  IMAPDATE     = "%d-%b-%Y"          # :nodoc:
  IMAPDATETIME = "%d-%b-%Y %H:%M %Z" # :nodoc:

  ##
  # Parse an IMAP date formatted string into a Time.

  def self.imapdate str
    Time.strptime str, IMAPDATE
  end

  ##
  # Parse an IMAP datetime formatted string into a Time.

  def self.imapdatetime str
    Time.strptime str, IMAPDATETIME
  end

  ##
  # Formats this Time as an IMAP-style date.

  def imapdate
    strftime IMAPDATE
  end

  ##
  # Formats this Time as an IMAP-style datetime.
  #
  # RFC 2060 doesn't specify the format of its times.  Unfortunately it is
  # almost but not quite RFC 822 compliant.
  #--
  # Go Mr. Leatherpants!

  def imapdatetime
    strftime IMAPDATETIME
  end

  ##
  # Format a date into YYYY-MM, common for mailbox extensions.

  def yyyy_mm
    strftime("%Y-%m")
  end
end
