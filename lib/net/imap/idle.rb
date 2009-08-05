require 'net/imap'

class Net::IMAP

  ##
  # Sends an IDLE command that waits for notifications of new or expunged
  # messages.  Yields responses from the server during the IDLE.
  #
  # Use #idle_done to leave IDLE.

  def idle(&response_handler)
    raise LocalJumpError, "no block given" unless response_handler

    response = nil

    synchronize do
      tag = Thread.current[:net_imap_tag] = generate_tag
      put_string "#{tag} IDLE#{CRLF}"

      begin
        add_response_handler response_handler

        @idle_done_cond = new_cond
        @idle_done_cond.wait
        @idle_done_cond = nil
      ensure
        remove_response_handler response_handler
        put_string "DONE#{CRLF}"
        response = get_tagged_response tag
      end
    end

    response
  end

  ##
  # Leaves IDLE

  def idle_done
    raise Net::IMAP::Error, 'not during idle' unless @idle_done_cond

    synchronize do
      @idle_done_cond.signal
    end
  end

end unless Net::IMAP.method_defined? :idle

