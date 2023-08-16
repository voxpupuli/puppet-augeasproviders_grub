# frozen_string_literal: true

# GRUB 2 support for menuentries, adds material to /etc/grub.d/05_puppet_controlled_*
#
# Copyright (c) 2016 Trevor Vaughan <tvaughan@onyxpoint.com>
# Licensed under the Apache License, Version 2.0

Puppet::Type.type(:grub_menuentry).provide(:grub2, parent: Puppet::Type.type(:augeasprovider).provider(:default)) do
  desc 'Provides for the manipulation of GRUB2 menuentries'

  has_feature :grub2

  # Populate the default methods
  mk_resource_methods

  #### Class Methods
  def self.mkconfig_path
    which('grub2-mkconfig') or which('grub-mkconfig') or '/usr/sbin/grub-mkconfig'
  end

  # Return an Array of system resources culled from a full GRUB2
  # mkconfig-generated configuration
  #
  # @param config (String) The output of grub2-mkconfig or the grub2.cfg file
  # @param current_default (String) The name of the current default GRUB entry
  # @return (Array) An Array of resource Hashes
  def self.grub2_mkconfig_menuentries(config, current_default)
    resources = []

    # Pull out the menuentries into our resources
    in_menuentry = false

    # We need to track these to set the default entry
    submenus = []
    resource = {}
    config.to_s.each_line do |line|
      submenus << Regexp.last_match(1) if line =~ %r{^\s*submenu (?:'|")(.*)(?:':")\s*\{}

      # The main menuentry line
      if line =~ %r{^\s*menuentry '(.+?)'}
        resource = {
          name: Regexp.last_match(1),
          bls: false
        }
        resource[:default_entry] = (resource[:name] == current_default)

        raise Puppet::Error, 'Malformed config file received' if in_menuentry

        in_menuentry = true

        menuentry_components = line.strip.split(%r{\s+})[1..-1]

        classes = []
        menuentry_components.each_index do |i|
          classes << menuentry_components[i + 1] if menuentry_components[i] == '--class'
        end

        resource[:classes] = classes unless classes.empty?

        users = []
        if menuentry_components.include?('--unrestricted')
          users = [:unrestricted]
        else
          menuentry_components.each_index do |i|
            if menuentry_components[i] == '--users'
              # This insanity per the GRUB2 user's guide
              users = menuentry_components[i + 1].strip.split(%r{\s|,|;|\||&})
            end
          end
        end

        resource[:users] = users unless users.empty?

        resource[:load_video]     = false
        resource[:load_16bit]     = false
        resource[:puppet_managed] = false
        resource[:modules] ||= []

      elsif in_menuentry
        case line
        when %r{^\s*load_video\s*$}
          resource[:load_video] = true

        when %r{^\s*insmod\s+(\S+)$}
          resource[:plugins] ||= []

          resource[:plugins] << Regexp.last_match(1).strip

        when %r{^\s*(?:set\s+)?root='(.+)'$}
          resource[:root] = Regexp.last_match(1).strip

        when %r{^\s*#### PUPPET MANAGED ####\s*$}
          resource[:puppet_managed] = true

        when %r{^\s*(?:multiboot|linux(16)?)(.+)}
          resource[:load_16bit] = true if Regexp.last_match(1) == '16'

          kernel_line = Regexp.last_match(2).strip.split(%r{\s+})
          resource[:kernel] = kernel_line.shift
          resource[:kernel_options] = kernel_line

        when %r{^\s*initrd(?:16)?(.+)}
          resource[:initrd] = Regexp.last_match(1).strip

        when %r{^\s*module\s+(.+)}
          resource[:modules] << Regexp.last_match(1).strip.split(%r{\s+})

        when %r{^\s*\}\s*$}
          in_menuentry = false
          if resource.empty?
            debug('Warning: menuentry resource was empty')
          else
            resource[:submenus] = submenus
            resources << resource
          end

          submenus = []
        end
      end
    end

    resources
  end

  # Return an Array of system resources based on processing the BLS stack
  #
  # This is required for systems that use the BLS Grub2 module
  #
  # @param current_default (String) The name of the current default GRUB entry
  # @return (Array) An Array of resource Hashes
  def self.grub2_bls_menuentries(current_default)
    resources = []

    begin
      grubenv = File.read('/boot/grub2/grubenv').lines.
                # Remove comments
                reject { |l| l.start_with?('#') }.
                # Create a hash of all of the key/value entries in the file
                map { |l| l.strip.split(%r{^(.+?)=(.+)$}).reject(&:empty?) }.to_h

      require 'puppet/util/package'
      # This is how grubby does it
      # See https://fedoraproject.org/wiki/Changes/BootLoaderSpecByDefault
      Dir.glob('/boot/loader/entries/*.conf').sort { |x, y| Puppet::Util::Package.versioncmp(y, x) }.each do |file|
        config = File.read(file)

        puppet_managed = config.include?('### PUPPET MANAGED ###')

        # Before we begin processing, replace all environment variables with their
        # corresponding setting from `grubenv` above
        #
        # This doesn't catch everything because we aren't processing the entire
        # grub2.cfg file but it's about the best we can do
        grubenv.each do |k, v|
          config.gsub!(%r{\$#{k}(\s+|$)}) { "#{v}#{Regexp.last_match(1)}" }
        end

        config = config.lines.map(&:strip)

        # Process out args that could occur multiple times
        #
        # The specs are completely unclear on how this actually works, so we're
        # taking a wild stab and assuming that plural things can be space
        # separated and non-plural things can only have one item.
        #
        users, config = config.partition { |x| x.match?(%r{^grub_users\s+}) }
        users.map! { |x| x.split(%r{\s+}) }
        users.flatten!
        users.delete('grub_users')
        users.sort

        args, config = config.partition { |x| x.match?(%r{^grub_arg\s+}) }
        args.map! { |x| x.split(%r{\s+}) }
        args.flatten!
        args.delete('grub_arg')
        args.sort

        classes, config = config.partition { |x| x.match?(%r{^grub_class\s+}) }
        classes.map! { |x| x.split(%r{\s+}) }
        classes.flatten!
        classes.delete('grub_class')
        classes.sort

        # Convert the rest of the config to a Hash for ease of use
        config = config.reject { |l| l.start_with?('#') }.map { |l| l.split(%r{^(.+?)\s+(.+)$}).reject(&:empty?) }.to_h

        resource = {
          name: config['title'],
          bls: true,
          bls_target: file,
          puppet_managed: puppet_managed,
          default_entry: false
        }

        resource[:default_entry] = (resource[:name] == current_default)

        if args.include?('--unrestricted')
          resource[:users] = [:unrestricted]
          args.delete('--unrestricted')
        elsif !users.empty?
          resource[:users] = users
        end

        resource[:args]           = args unless args.empty?
        resource[:classes]        = classes unless classes.empty?
        resource[:kernel]         = config['linux']
        resource[:kernel_options] = config['options']
        resource[:initrd]         = config['initrd']

        resources << resource
      end
    rescue StandardError => e
      debug("Exception while processing BLS entries => #{e}")
    end

    resources
  end

  # Return an Array of system resources culled from the system GRUB2
  # configuration
  #
  # @param config (String) The output of grub2-mkconfig or the grub2.cfg file
  # @param current_default (String) The name of the current default GRUB entry
  # @return (Array) An Array of resource Hashes
  def self.grub2_menuentries(config, current_default)
    resources = grub2_mkconfig_menuentries(config, current_default)
    resources += grub2_bls_menuentries(current_default) if config.match?(%r{^blscfg$})

    resources
  end

  def self.instances
    require 'puppetx/augeasproviders_grub/util'

    @grubby_default_index ||= (grubby '--default-index').strip

    current_default = nil
    current_default = Regexp.last_match(1).delete('"') if (grubby "--info=#{@grubby_default_index}") =~ %r{^\s*title=(.+)\s*$}

    grub2_menuentries(PuppetX::AugeasprovidersGrub::Util.grub2_cfg, current_default).map { |x| new(x) }
  end

  def self.prefetch(resources)
    instances.each do |prov|
      if (resource = resources[prov.name])
        resource.provider = prov
      end
    end
  end

  #### End Class Methods

  confine exists: mkconfig_path, for_binary: true

  def mkconfig
    execute(self.class.mkconfig_path, { failonfail: true, combine: false })
  end

  commands grubby: 'grubby'
  commands grub_set_default: 'grub2-set-default'

  confine exists: '/etc/grub.d'

  defaultfor osfamily: :RedHat

  def initialize(*args)
    super(*args)

    require 'puppetx/augeasproviders_grub/util'

    @grubby_info = {}
    begin
      @grubby_default_index = (grubby '--default-index').strip
      grubby_raw = grubby "--info=#{@grubby_default_index}"

      grubby_raw.each_line do |opt|
        key, val = opt.to_s.split('=')

        @grubby_info[key.strip] = val.strip.delete('"')
      end
    rescue Puppet::ExecutionFailure
      @grubby_info = {}
    end

    current_default = (@grubby_info['title']) if @grubby_info['title']

    # Things that we really only want to do once...
    menu_entries = self.class.grub2_menuentries(PuppetX::AugeasprovidersGrub::Util.grub2_cfg, current_default)

    # These only matter if we're trying to manipulate a resource

    # Extract the default entry for reference later
    @default_entry = menu_entries.select { |x| x[:default_entry] }.first
    raise(Puppet::Error, 'Could not find a default GRUB2 entry. Check your system grub configuration using `grubby --info=`grubby --default-index``') unless @default_entry

    @bls_system = (menu_entries.find { |x| x[:bls] } ? true : false)
  end

  # Prepping material here for use in other functions since this is always
  # called first.
  def exists?
    require 'openssl'

    @property_hash[:id] = OpenSSL::Digest.new('SHA256').digest(name).unpack1('H*')

    @property_hash[:target] = resource[:target] if resource[:target]
    @property_hash[:add_defaults_on_creation] = resource[:add_defaults_on_creation]
    @property_hash[:classes] ||= resource[:classes] || []

    @property_hash[:bls] = @bls_system && (@property_hash[:bls] || (@property_hash[:bls].nil? && (resource[:bls].nil? || resource[:bls])))

    # BLS and non-BLS systems must be treated differently
    if @property_hash[:bls] || resource[:bls]
      @property_hash[:args] ||= []
    else
      @property_hash[:load_16bit] ||= resource[:load_16bit].nil? ? true : resource[:load_16bit]
      @property_hash[:load_video] ||= resource[:load_video].nil? ? true : resource[:load_video]
      @property_hash[:plugins] ||= resource[:plugins].nil? ? %w[gzio part_msdos xfs ext2] : resource[:plugins]
    end

    retval = @property_hash[:name] == resource[:name]
    unless resource[:bls].nil?
      retval &&= (resource[:bls] == @property_hash[:bls])
      @property_hash[:bls] = resource[:bls]
    end

    retval
  end

  def create
    # Input Validation
    raise Puppet::Error, '`root` is a required property' if !bls && !resource[:root]
    raise Puppet::Error, '`kernel` is a required property' unless resource[:kernel]
    raise Puppet::Error, '`initrd` is a required parameter' unless resource[:modules] || resource[:initrd]

    # End Validation

    @property_hash[:create_output]  = true
    @property_hash[:users]          = resource[:users] || []
    @property_hash[:initrd]         = get_initrd('', resource[:initrd])
    @property_hash[:kernel]         = get_kernel('', resource[:kernel])
    @property_hash[:kernel_options] = get_kernel_options([], resource[:kernel_options])[:new_kernel_options]
    @property_hash[:modules]        = get_module_options([], resource[:modules])[:new_module_options]
    @property_hash[:default_entry]  = resource[:default_entry]

    if bls
      @property_hash[:classes] = resource[:classes] || ['kernel']
    else
      @property_hash[:classes]    = resource[:classes] || []
      @property_hash[:root]       = resource[:root]
      @property_hash[:load_16bit] = resource[:load_16bit]
      @property_hash[:load_video] = resource[:load_video]
      @property_hash[:plugins]  ||= resource[:plugins].nil? ? %w[gzio part_msdos xfs ext2] : resource[:plugins]
    end
  end

  def destroy
    @property_hash[:destroy] = true
  end

  def classes=(newval)
    @property_hash[:classes] = newval
  end

  def users=(newval)
    @property_hash[:users] = newval
  end

  def load_16bit=(newval)
    @property_hash[:load_16bit] = newval
  end

  def load_video
    bls ? resource[:load_video] : @property_hash[:load_video]
  end

  def load_video=(newval)
    @property_hash[:load_video] = newval
  end

  def plugins
    bls ? resource[:plugins] : @property_hash[:plugins]
  end

  def plugins=(newval)
    @property_hash[:plugins] = newval
  end

  def root
    bls ? resource[:root] : @property_hash[:root]
  end

  def root=(newval)
    @property_hash[:root] = newval
  end

  def kernel?(is, should)
    return true unless should

    @new_kernel = get_kernel(is, should)

    is == @new_kernel
  end

  def kernel=(_newval)
    @property_hash[:kernel] = @new_kernel
  end

  def kernel_options?(is, should)
    kernel_options = get_kernel_options(is, should)

    @new_kernel_options = kernel_options[:new_kernel_options]
    kernel_options[:old_kernel_options] == @new_kernel_options
  end

  def kernel_options=(newval)
    @new_kernel_options = Array(newval) if @new_kernel_options.empty?

    default_kernel_options = @default_entry[:kernel_options]
    if resource[:modules]
      # We don't want to pick up any default kernel options if this is a multiboot entry.
      default_kernel_options = {}
    end

    @new_kernel_options = PuppetX::AugeasprovidersGrub::Util.munged_options([], @new_kernel_options, @default_entry[:kernel], default_kernel_options)

    @property_hash[:kernel_options] = @new_kernel_options.join(' ')
  end

  def modules?(is, should)
    module_options = get_module_options(is, should)

    @new_module_options = module_options[:new_module_options]

    module_options[:old_module_options] == @new_module_options
  end

  def get_module_options(is, should, default_entry = @default_entry)
    new_module_options = []
    old_module_options = []

    i = 0
    Array(should).each do |module_set|
      module_set << ':defaults:' if @property_hash[:create_output] && @property_hash[:add_defaults_on_creation] && module_set.include?(':preserve:')

      current_val = Array(Array(is)[i])
      new_module_options << PuppetX::AugeasprovidersGrub::Util.munged_options(current_val, module_set, default_entry[:kernel], default_entry[:kernel_options], true)

      old_module_options << PuppetX::AugeasprovidersGrub::Util.munged_options(current_val, ':preserve:', default_entry[:kernel], default_entry[:kernel_options], true) unless current_val.empty?

      i += 1
    end

    { new_module_options: new_module_options, old_module_options: old_module_options }
  end

  def modules=(newval)
    new_module_options = @new_module_options

    if Array(new_module_options).empty?
      new_module_options = []
      Array(newval).each do |module_set|
        new_module_options << PuppetX::AugeasprovidersGrub::Util.munged_options([], module_set, @default_entry[:kernel], @default_entry[:kernel_options])
      end
    end

    @property_hash[:modules] = new_module_options
  end

  def initrd?(is, should)
    return true unless should

    @new_initrd = get_initrd(is, should)

    is == @new_initrd
  end

  def initrd=(_newval)
    @property_hash[:initrd] = @new_initrd
  end

  def flush
    super

    require 'puppetx/augeasproviders_grub/util'

    @property_hash[:name] = name

    if @property_hash[:kernel] =~ %r{(\d.+)}
      bls_version = Regexp.last_match(1)
    else
      bls_version = @property_hash[:kernel].dup
      bls_version.delete('/')
    end

    bls_target = @property_hash[:bls_target] ||
                 File.join('',
                           'boot',
                           'loader',
                           'entries',
                           "#{@property_hash[:id][0...32]}-#{bls_version}.conf")

    legacy_target = @property_hash[:target] ||
                    "/etc/grub.d/05_puppet_managed_#{@property_hash[:id].upcase[0...10]}"

    output = []

    if bls
      if @property_hash[:destroy]
        FileUtils.rm_f(property_hash[:bls_target])
      else

        @property_hash[:target] = if @property_hash[:bls_target] && !@property_hash[:target]
                                    @property_hash[:bls_target]
                                  else
                                    bls_target
                                  end

        output = construct_bls_entry(@property_hash, bls_version)

        File.open(@property_hash[:target], 'w') do |fh|
          fh.puts(output.join("\n"))
          fh.flush
        end

        FileUtils.chmod(0o644, @property_hash[:target])

        if File.exist?(legacy_target)
          FileUtils.rm_f(legacy_target)

          # Need to rebuild the full grub config if we removed a legacy target
          PuppetX::AugeasprovidersGrub::Util.grub2_mkconfig(mkconfig)
        end
      end
    elsif @property_hash[:destroy]
      FileUtils.rm_f(legacy_target)
      return
    else
      @property_hash[:load_16bit] = resource[:load_16bit]
      @property_hash[:add_defaults_on_creation] = resource[:add_defaults_on_creation]

      if !@property_hash[:create_output] && !File.exist?(legacy_target)
        # If we have a modification request, but the target file does not exist,
        # this means that the entry was picked up from something that is not
        # Puppet managed and is an error.
        raise Puppet::Error, 'Cannot modify a stock system resource; please change your resource :name'
      end

      output = construct_grub2cfg_entry(@property_hash)

      File.open(legacy_target, 'w') do |fh|
        fh.puts(output.join("\n"))
        fh.flush
      end

      FileUtils.chmod(0o755, legacy_target)

      # Need to remove the BLS config if we moved it to be legacy
      FileUtils.rm_f(bls_target) if File.exist?(bls_target)

      PuppetX::AugeasprovidersGrub::Util.grub2_mkconfig(mkconfig)
    end

    grub_set_default (Array(@property_hash[:submenus]) + Array(@property_hash[:name])).compact.join('>').to_s if @property_hash[:default_entry]
  end

  private

  def get_kernel(is, should, grubby_info = @grubby_info)
    new_kernel = should

    if new_kernel == ':preserve:'
      new_kernel = is
      new_kernel = ':default:' if !new_kernel || new_kernel.empty?
    end

    new_kernel = PuppetX::AugeasprovidersGrub::Util.munge_grubby_value(new_kernel, 'kernel', grubby_info) if new_kernel == ':default:'

    raise Puppet::Error, 'Could not find a valid kernel value to set' unless new_kernel

    new_kernel
  end

  def get_kernel_options(is, should, default_entry = @default_entry)
    should << ':defaults:' if @property_hash[:create_output] && @property_hash[:add_defaults_on_creation] && should.include?(':preserve:')

    default_kernel_options = default_entry[:kernel_options]
    if resource[:modules]
      # We don't want to pick up any default kernel options if this is a multiboot entry.
      default_kernel_options = {}
    end

    new_kernel_options = PuppetX::AugeasprovidersGrub::Util.munged_options(is, should, default_entry[:kernel], default_kernel_options)

    old_kernel_options = PuppetX::AugeasprovidersGrub::Util.munged_options(is, ':preserve:', default_entry[:kernel], default_entry[:kernel_options])

    { new_kernel_options: new_kernel_options, old_kernel_options: old_kernel_options }
  end

  def get_initrd(is, should, grubby_info = @grubby_info)
    new_initrd = should

    if new_initrd == ':preserve:'
      new_initrd = is
      new_initrd = ':default:' if !new_initrd || new_initrd.empty?
    end

    new_initrd = PuppetX::AugeasprovidersGrub::Util.munge_grubby_value(new_initrd, 'initrd', grubby_info) if new_initrd == ':default:'

    raise Puppet::Error, 'Could not find a valid initrd value to set' unless new_initrd

    new_initrd
  end

  def construct_bls_entry(property_hash, bls_version, header_comment = '### PUPPET MANAGED ###')
    output = []

    output << header_comment
    output << "title #{property_hash[:name]}"
    output << "version #{bls_version}"
    output << "linux #{property_hash[:kernel]}"
    output << "initrd #{property_hash[:initrd]}"
    output << "options #{Array(property_hash[:kernel_options]).join(' ')}"
    output << "id #{property_hash[:id]}-#{bls_version}"

    if property_hash[:users].include?('unrestricted') || property_hash[:users].include?(:unrestricted)
      property_hash[:users].delete(:unrestricted)
      property_hash[:users].delete('unrestricted')

      output << 'grub_arg --unrestricted'
    end

    output << if property_hash[:users].empty?
                'grub_users $grub_users'
              else
                "grub_users #{property_hash[:users].join(' ')}"
              end

    property_hash[:args].each do |arg|
      output << "grub_arg #{arg}"
    end

    property_hash[:classes].each do |cls|
      output << "grub_class #{cls}"
    end

    output
  end

  def construct_grub2cfg_entry(_property_hash, header_comment = '### PUPPET MANAGED ###')
    output = []

    output << '#!/bin/sh'

    # We use this to determine if we're puppet managed or not
    output << header_comment
    output << 'exec tail -n +3 $0'

    # Build the main menuentry line
    menuentry_line = ["menuentry '#{@property_hash[:name]}'"]

    menuentry_line << @property_hash[:classes].map { |x| "--class #{x}" }.join(' ')

    unless @property_hash[:users].empty?
      menuentry_line << if @property_hash[:users].include?('unrestricted') || @property_hash[:users].include?(:unrestricted)
                          '--unrestricted'
                        else
                          "--users #{@property_hash[:users].join(',')}"
                        end
    end

    menuentry_line << '{'

    output << menuentry_line.join(' ')
    # Main menuentry line complete

    output << '  load_video' if @property_hash[:load_video]

    output += @property_hash[:plugins].map { |x| %(  insmod #{x}) } if @property_hash[:plugins]

    output << %(  set root='#{@property_hash[:root]}')

    # Build the main kernel line
    kernel_line = []

    # If we have modules defined, we're in multiboot mode
    if @property_hash[:modules] && !@property_hash[:modules].empty?
      output << '  insmod multiboot2' if File.exist?('/sys/firmware/efi')

      kernel_line << '  multiboot'
    else
      kernel_line << if @property_hash[:load_16bit]
                       '  linux16'
                     else
                       '  linux'
                     end
    end

    kernel_line << @property_hash[:kernel]
    kernel_line << @property_hash[:kernel_options]

    output << kernel_line.flatten.compact.join(' ')

    if @property_hash[:modules].empty?
      output << if @property_hash[:load_16bit]
                  %(  initrd16 #{@property_hash[:initrd]})
                else
                  %(  initrd #{@property_hash[:initrd]})
                end
    else
      @property_hash[:modules].each do |mod|
        output << %(  module #{mod.compact.join(' ')})
      end
    end

    output << '}'

    output
  end
end
