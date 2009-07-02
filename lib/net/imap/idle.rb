require 'net/imap'

class Net::IMAP

  ##
  # Sends an IDLE command that waits for notifications of new or expunged
  # messages.  Yields responses from the server during the IDLE.
  #
  # Use +break+ in the response handler to leave IDLE.

  def idle(&response_handler)
    raise LocalJumpError, "no block given" unless response_handler

    response = nil

    synchronize do
      tag = Thread.current[:net_imap_tag] = generate_tag
      put_string "#{tag} IDLE#{CRLF}"

      add_response_handler response_handler

      begin
        response = get_tagged_response tag
      rescue LocalJumpError # can't break cross-threads or something
      ensure
        unless response then
          put_string "DONE#{CRLF}"
          response = get_tagged_response tag
        end

        remove_response_handler response_handler
      end
    end

    response
  end

end

