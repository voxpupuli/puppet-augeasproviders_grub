# GRUB 2 support for menuentries, adds material to /etc/grub.d/05_puppet_controlled_*
#
# Copyright (c) 2016 Trevor Vaughan <tvaughan@onyxpoint.com>
# Licensed under the Apache License, Version 2.0

Puppet::Type.type(:grub_menuentry).provide(:grub2) do
  desc "Provides for the manipulation of GRUB2 menuentries"

  has_feature :grub2

  #### Class Methods
  def self.mkconfig_path
    which("grub2-mkconfig") or which("grub-mkconfig") or '/usr/sbin/grub-mkconfig'
  end

  # Return an Array of system resources culled from a full GRUB2
  # configuration
  #
  # @param config (String) The output of grub2-mkconfig or the grub2.cfg file
  # @param current_default (String) The name of the current default GRUB entry
  # @return (Array) An Array of resource Hashes
  def self.grub2_menuentries(config, current_default)
    resources = []

    # Pull out the menuentries into our resources
    in_menuentry = false

    # We need to track these to set the default entry
    submenus = []
    resource = {}
    config.to_s.each_line do |line|
      if line =~ /^\s*submenu (?:'|")(.*)(?:':")\s*\{/
        submenus << $1
      end

      # The main menuentry line
      if line =~ /^\s*menuentry '(.+?)'/
        resource = {
          :name => $1
        }

        if resource[:name] == current_default
          resource[:default_entry] = true
        else
          resource[:default_entry] = false
        end

        if in_menuentry
          raise Puppet::Error, "Malformed config file received"
        end

        in_menuentry = true

        menuentry_components = line.strip.split(/\s+/)[1..-1]

        classes = []
        menuentry_components.each_index do |i|
          if menuentry_components[i] == '--class'
            classes << menuentry_components[i+1]
          end
        end

        resource[:classes] = classes unless classes.empty?

        users = []
        if menuentry_components.include?('--unrestricted')
          users = [:unrestricted]
        else
          menuentry_components.each_index do |i|
            if menuentry_components[i] == '--users'
              # This insanity per the GRUB2 user's guide
              users = menuentry_components[i+1].strip.split(/\s|,|;|\||&/)
            end
          end
        end

        resource[:users] = users unless users.empty?

        resource[:load_video]     = false
        resource[:load_16bit]     = false
        resource[:puppet_managed] = false
        resource[:modules] ||= []

      elsif in_menuentry
        if line =~ /^\s*load_video\s*$/
          resource[:load_video] = true

        elsif line =~ /^\s*insmod\s+(\S+)$/
          resource[:plugins] ||= []

          resource[:plugins] << $1.strip

        elsif line =~ /^\s*(?:set\s+)?root='(.+)'$/
          resource[:root] = $1.strip

        elsif line =~ /^\s*#### PUPPET MANAGED ####\s*$/
          resource[:puppet_managed] = true

        elsif line =~ /^\s*(?:multiboot|linux(16)?)(.+)/
          if $1 == '16'
            resource[:load_16bit] = true
          end

          kernel_line = $2.strip.split(/\s+/)
          resource[:kernel] = kernel_line.shift
          resource[:kernel_options] = kernel_line

        elsif line =~ /^\s*initrd(?:16)?(.+)/
          resource[:initrd] = $1.strip

        elsif line =~ /^\s*module\s+(.+)/
          resource[:modules] << $1.strip.split(/\s+/)

        elsif line =~ /^\s*\}\s*$/
          in_menuentry = false
          if resource.empty?
            debug("Warning: menuentry resource was empty")
          else
            resource[:submenus] = submenus
            resources << resource
          end

          submenus = []
        end
      end
    end

    return resources
  end

  def self.instances
    require 'puppetx/augeasproviders_grub/menuentry'

    if (grubby '--info=DEFAULT') =~ /^\s*title=(.+)\s*$/
      current_default = ($2.to_i - 1)
    end

    grub2_menuentries(PuppetX::AugeasprovidersGrub::Util.grub2_cfg, current_default).map{|x| x = new(x)}
  end
  #### End Class Methods

  commands :mkconfig => mkconfig_path
  commands :grubby => 'grubby'
  commands :grub_set_default => 'grub2-set-default'

  confine :exists => '/etc/grub.d'

  defaultfor :osfamily => :RedHat

  def initialize(*args)
    super(*args)

    require 'puppetx/augeasproviders_grub/menuentry'

    @grubby_info = {}
    begin
      grubby_raw = grubby '--info=DEFAULT'

      grubby_raw.each_line do |opt|
        key,val = opt.to_s.split('=')

        @grubby_info[key.strip] = val.strip
      end
    rescue Puppet::ExecutionFailure
      @grubby_info = {}
    end

    if @grubby_info['title']
      current_default = (@grubby_info['title'])
    end

    # Things that we really only want to do once...
    @menu_entries = self.class.grub2_menuentries(PuppetX::AugeasprovidersGrub::Util.grub2_cfg, current_default)

    current_index = @menu_entries.index { |x| x[:name] == self.name }

    if current_index
      @current_entry = @menu_entries[current_index]
    else
      @current_entry = {}
    end

    # These only matter if we're trying to manipulate a resource

    # Extract the default entry for reference later
    @default_entry = @menu_entries.select{|x| x[:default_entry] }.first
    raise(Puppet::Error, "Could not find a default GRUB2 entry. Check your system grub configuration using `grubby --info=DEFAULT`") unless @default_entry

    require 'openssl'
    random_file_ext = OpenSSL::Digest::SHA256.new.digest(self.name).unpack('H*').first.upcase[0..11]
    @new_entry = @current_entry.dup

    @new_entry[:name] = self.name
    @new_entry[:output_file] = "/etc/grub.d/05_puppet_managed_#{random_file_ext}"
  end

  def exists?
    @new_entry[:load_16bit] = (resource[:load_16bit] == :true)
    @new_entry[:add_defaults_on_creation] = (resource[:add_defaults_on_creation] == :true)

    !@current_entry.empty?
  end

  def create
    # Input Validation
    fail Puppet::Error, '`kernel` is a required property' unless resource[:kernel]
    fail Puppet::Error, '`root` is a required property' unless resource[:root]

    unless resource[:modules]
      fail Puppet::Error, '`initrd` is a required parameter' unless resource[:initrd]
    end
    # End Validation

    @new_entry[:create_output] = true

    self.root=(resource[:root])

    # Need to prime this to reduce duplication later
    self.kernel?([],resource[:kernel])
    self.kernel=(resource[:kernel])

    if resource[:users]
      self.users=(resource[:users])
    end

    if resource[:classes]
      self.classes=(resource[:classes])
    end

    if resource[:load_video]
      self.load_video=(resource[:load_video])
    end

    if resource[:plugins]
      self.plugins=(resource[:plugins])
    end

    # Need to prime this to reduce duplication later
    self.initrd?([],resource[:initrd])
    self.initrd=(resource[:initrd])

    if resource[:kernel_options]
      # Need to prime this to reduce duplication later
      self.kernel_options?([],resource[:kernel_options])
      self.kernel_options=(resource[:kernel_options])
    end

    if resource[:modules]
      # Need to prime this to reduce duplication later
      self.modules?([],resource[:modules])
      self.modules=(resource[:modules])
    end

    if resource[:default_entry]
      self.default_entry=(resource[:default_entry])
    end
  end

  def destroy
    if File.exist?(@new_entry[:output_file])
      FileUtils.rm_f(@new_entry[:output_file])
    end
  end

  def classes
    @current_entry[:classes]
  end

  def classes=(newval)
    @new_entry[:classes] = newval
  end

  def users
    if @current_entry[:users]
      Array(Array(@current_entry[:users]).join(','))
    end
  end

  def users=(newval)
    @new_entry[:users] = newval
  end

  def load_video
    @current_entry[:load_video].to_s.to_sym
  end

  def load_video=(newval)
    @new_entry[:load_video] = (newval == :true)
  end

  def plugins
    @current_entry[:plugins]
  end

  def plugins=(newval)
    @new_entry[:plugins] = newval
  end

  def default_entry
    @current_entry[:default_entry].to_s.to_sym
  end

  def default_entry=(newval)
    @new_entry[:default_entry] = (newval.to_s == 'true')
  end

  def root
    @current_entry[:root]
  end

  def root=(newval)
    @new_entry[:root] = newval
  end

  def kernel
    @current_entry[:kernel]
  end

  def kernel?(is,should)
    return true unless should

    @new_kernel = should

    if @new_kernel == ':preserve:'
      @new_kernel = is
      if !@new_kernel || @new_kernel.empty?
        @new_kernel = ':default:'
      end
    end

    if @new_kernel == ':default:'
      @new_kernel = PuppetX::AugeasprovidersGrub::Util.munge_grubby_value(@new_kernel, 'kernel', @grubby_info)
    end

    unless @new_kernel
      raise Puppet::Error, 'Could not find a valid kernel value to set'
    end

    is == @new_kernel
  end

  def kernel=(newval)
    @new_entry[:kernel] = @new_kernel
  end

  def kernel_options
    @current_entry[:kernel_options]
  end

  def kernel_options?(is,should)
    if @new_entry[:create_output] && @new_entry[:add_defaults_on_creation] && should.include?(':preserve:')
      should << ':defaults:'
    end

    default_kernel_options = @default_entry[:kernel_options]
    if resource[:modules]
      # We don't want to pick up any default kernel options if this is a multiboot entry.
      default_kernel_options = {}
    end

    @new_kernel_options = PuppetX::AugeasprovidersGrub::Util.munged_options(is, should, @default_entry[:kernel], default_kernel_options)
    old_options = PuppetX::AugeasprovidersGrub::Util.munged_options(is, ':preserve:', @default_entry[:kernel], @default_entry[:kernel_options])

    old_options == @new_kernel_options
  end

  def kernel_options=(newval)
    if @new_kernel_options.empty?
      @new_kernel_options = Array(newval)
    end

    default_kernel_options = @default_entry[:kernel_options]
    if resource[:modules]
      # We don't want to pick up any default kernel options if this is a multiboot entry.
      default_kernel_options = {}
    end

    @new_kernel_options = PuppetX::AugeasprovidersGrub::Util.munged_options([], @new_kernel_options, @default_entry[:kernel], default_kernel_options)

    @new_entry[:kernel_options] = @new_kernel_options.join(' ')
  end

  def modules
    @current_entry[:modules]
  end

  def modules?(is,should)
    @new_modules_options = []
    old_options = []

    i = 0
    Array(should).each do |module_set|
      if @new_entry[:create_output] && @new_entry[:add_defaults_on_creation] && module_set.include?(':preserve:')
        module_set << ':defaults:'
      end

      current_val = Array(Array(is)[i])
      @new_modules_options << PuppetX::AugeasprovidersGrub::Util.munged_options(current_val, module_set, @default_entry[:kernel], @default_entry[:kernel_options], true)

      unless current_val.empty?
        old_options << PuppetX::AugeasprovidersGrub::Util.munged_options(current_val, ':preserve:', @default_entry[:kernel], @default_entry[:kernel_options], true)
      end

      i += 1
    end

    old_options == @new_modules_options
  end

  def modules=(newval)
    new_modules_options = @new_modules_options

    if Array(new_modules_options).empty?
      new_modules_options = []
      Array(newval).each do |module_set|
        new_modules_options << PuppetX::AugeasprovidersGrub::Util.munged_options([], module_set, @default_entry[:kernel], @default_entry[:kernel_options])
      end
    end

    @new_entry[:modules] = new_modules_options
  end

  def initrd
    @current_entry[:initrd]
  end

  def initrd?(is,should)
    return true unless should

    @new_initrd = should

    if @new_initrd == ':preserve:'
      @new_initrd = is
      if !@new_initrd || @new_initrd.empty?
        @new_initrd = ':default:'
      end
    end

    if @new_initrd == ':default:'
      @new_initrd = PuppetX::AugeasprovidersGrub::Util.munge_grubby_value(@new_initrd, 'initrd', @grubby_info)
    end

    unless @new_initrd
      raise Puppet::Error, 'Could not find a valid initrd value to set'
    end

    is == @new_initrd
  end

  def initrd=(newval)
    @new_entry[:initrd] = @new_initrd
  end

  def flush
    unless @new_entry[:create_output]
      # If we have a modification request, but the target file does not exist,
      # this means that the entry was picked up from something that is not
      # Puppet managed and is an error.
      unless File.exist?(@new_entry[:output_file])
        raise Puppet::Error, 'Cannot modify a stock system resource; please change your resource :name'
      end
    end

    output = []

    output << '#!/bin/sh'

    # We use this to determine if we're puppet managed or not
    output << '#### PUPPET MANAGED ####'
    output << 'exec tail -n +3 $0'

    # Build the main menuentry line
    menuentry_line = ["menuentry '#{@new_entry[:name]}'"]

    if @new_entry[:classes] && !@new_entry[:classes].empty?
      menuentry_line << @new_entry[:classes].map{|x| x = "--class #{x}"}.join(' ')
    end

    if @new_entry[:users] && !@new_entry[:users].empty?
      if @new_entry[:users].map{|x| x.to_s}.include?('unrestricted')
        menuentry_line << '--unrestricted'
      else
        menuentry_line << "--users #{@new_entry[:users].join(',')}"
      end
    end

    menuentry_line << '{'

    output << menuentry_line.join(' ')
    # Main menuentry line complete

    output << '  load_video' if @new_entry[:load_video]

    output += @new_entry[:plugins].map{|x| x = %(  insmod #{x})} if @new_entry[:plugins]

    output << %(  set root='#{@new_entry[:root]}')

    # Build the main kernel line
    kernel_line = []

    # If we have modules defined, we're in multiboot mode
    if @new_entry[:modules] && !@new_entry[:modules].empty?
      if File.exist?('/sys/firmware/efi')
        output << '  insmod multiboot2'
      end

      kernel_line << '  multiboot'
    else
      if @new_entry[:load_16bit]
        kernel_line << '  linux16'
      else
        kernel_line << '  linux'
      end
    end

    kernel_line << @new_entry[:kernel]
    kernel_line << @new_entry[:kernel_options]
    output << kernel_line.compact.join(' ')

    if @new_entry[:modules] && !@new_entry[:modules].empty?
      @new_entry[:modules].each do |mod|
        output << %(  module #{mod.compact.join(' ')})
      end
    else
      if @new_entry[:load_16bit]
        output << %(  initrd16 #{@new_entry[:initrd]})
      else
        output << %(  initrd #{@new_entry[:initrd]})
      end
    end

    output << '}'

    fh = File.open(@new_entry[:output_file], 'w')
    fh.puts(output.join("\n"))
    fh.flush
    fh.close

    FileUtils.chmod(0755, @new_entry[:output_file])

    cfg = nil
    ["/etc/grub2.cfg", "/boot/grub/grub.cfg", "/boot/grub2/grub.cfg"].each {|c|
      cfg = c if FileTest.file? c
    }
    fail("Cannot find grub.cfg location to use with #{command(:mkconfig)}") unless cfg

    mkconfig "-o", cfg

    if @new_entry[:default_entry]
      grub_set_default %(#{(Array(@new_entry[:submenus]) + Array(@new_entry[:name])).compact.join('>')})
    end
  end
end
