
class Time

  ##
  # Formats this Time as an IMAP-style date.

  def imapdate
    strftime '%d-%b-%Y'
  end

  ##
  # Formats this Time as an IMAP-style datetime.
  #
  # RFC 2060 doesn't specify the format of its times.  Unfortunately it is
  # almost but not quite RFC 822 compliant.
  #--
  # Go Mr. Leatherpants!

  def imapdatetime
    strftime '%d-%b-%Y %H:%M %Z'
  end

end

