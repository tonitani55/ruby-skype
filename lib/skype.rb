
require 'skype/errors/exception_factory'
require 'skype/data_maps/user_visibility'

# This class is the main interface between Ruby and Skype.
class Skype
  private

  def platform
    @platform ||=
      case RbConfig::CONFIG['host_os']
        when /mingw|cygwin|mswin/
          :windows
        when /linux/
          :linux
        else
          :unknown
      end
  end

  public

  # Initialises the Skype library and sets up a communication protocol, but
  # doesn't connect yet.
  #
  # @param [String] application_name Name to use when identifying to Skype. Not
  #     all platforms use this value as Skype will automatically assign a name.
  def initialize(application_name, communication_protocol = nil)
    if communication_protocol.nil?
      case platform
        when :windows
          require 'skype/communication/windows'
          @skype = Skype::Communication::Windows.new(application_name)
        when :linux
          require 'skype/communication/dbus'
          @skype = Skype::Communication::DBus.new(application_name)
        else
          puts "Unfortunately, we don't support your platform currently."
          puts "Please file an issue if you think this is incorrect."
          exit 1
      end
    else
      @skype = communication_protocol
    end

    @skype.add_observer(self, :received_command)
  end

  # Controls whether the library should output extra debugging information or
  # not. Currently controls whether we should output all network throughput.
  #
  # @return [Boolean]
  def self.DEBUG
    @debug_mode
  end

  # (see DEBUG)
  def self.DEBUG=(value)
    @debug_mode = value
  end

  # Returns the currently in use version of the ruby-skype library.
  #
  # @return [String]
  def self.VERSION
    @version ||=
        IO.read(File.join(File.dirname(__FILE__), '..', 'VERSION')).chomp
  end

  # Connect to Skype and negotiate a communication channel. Blocks till the
  # connection is fully established.
  #
  # @return [Symbol] Initial value for user_status.
  def connect
    @skype.connect

    until @user_status
      tick
      sleep(0.1)
    end
    @user_status
  end

  # Are we connected to Skype?
  #
  # @return [Boolean]
  def connected?
    @skype.connected?
  end

  # Execute a single run of the Skype event loop
  #
  # @return [void]
  def tick
    @skype.tick
  end

  # Executes the Skype event loops. Doesn't return unless #quit is called.
  #
  # @return [void]
  def run
    @finished = false
    until @finished
      tick
      sleep(0.1)
    end
  end

  # Stops the Skype event loop from running.
  #
  # @return [void]
  def quit
    @finished = true
  end

  # Sends a raw command to Skype
  #
  # @param [String] command The command to send
  # @return [String] The value returned by Skype
  # @api private
  def send_raw_command(command)
    send_message(command)
  end

  #######################
  ###                 ###
  ### BEGIN SKYPE API ###
  ###                 ###
  #######################

  # Network connection status.
  #
  # Valid values:
  #
  #  * `:offline`
  #  * `:connecting`
  #  * `:pausing`
  #  * `:online`
  #
  # @return [Symbol]
  # @api skype
  attr_reader :connection_status

  # @!attribute [rw] user_status
  # User visibility for the current user.
  #
  # Valid values:
  #
  #  * `:unknown`
  #  * `:online`
  #  * `:offline`
  #  * `:skype_me`
  #  * `:away`
  #  * `:not_available`
  #  * `:do_not_disturb`
  #  * `:invisible`
  #
  # @return [Symbol]
  # @api skype
  def user_status
    @user_status
  end

  # (see #user_status)
  def user_status=(value)
    send_message("SET USERSTATUS " + DataMaps::USER_VISIBILITY[value])
    nil
  end

  # The protocol version in use for the connection with Skype. This value is
  # only reliable once connected.
  #
  # @return [Integer] The version number of the protocol in use.
  def protocol_version
    @skype.protocol_version
  end

  protected

  # Callback for receiving updates from Skype.
  #
  # @param [String] command The command string to process.
  # @return [void]
  def received_command(command)
    (command, args) = command.split(/\s+/, 2)
    case command
      when "CONNSTATUS"
        @connection_status = args.downcase.to_sym
      when "USERSTATUS"
        @user_status = DataMaps::USER_VISIBILITY.invert[args]
      else
    end
    puts "<= #{command} #{args}" if ::Skype.DEBUG
  end

  private

  # Handles sending messages and handling possible errors returned by Skype
  #
  # @param [String] message The message to send to Skype
  # @return [String] The reply from Skype or throws an exception on an error
  def send_message(message)
    ret = @skype.send(message)
    if ret[0,6] == "ERROR "
      Errors::ExceptionFactory.generate_exception(ret)
    end
    ret
  end
end
