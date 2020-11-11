# frozen_string_literal: true

# GRUB 2 support for kernel parameters, edits /boot/grub2/grubenv for BLSCFG
#
# Licensed under the Apache License, Version 2.0

raise('Missing augeasproviders_core dependency') if Puppet::Type.type(:augeasprovider).nil?

Puppet::Type.type(:kernel_parameter).provide(:grub2bls, parent: Puppet::Type.type(:augeasprovider).provider(:default)) do
  desc "Uses Augeas API to update kernel parameters in GRUB2's /boot/grub2/grubenv for BLSCFG"

  default_file { '/boot/grub2/grubenv' }

  # puppet may not have grubenv lense
  lens { 'Simplevars.lns' }

  defaultfor osfamily: 'Redhat', operatingsystemmajrelease: ['8']
  defaultfor osname: 'Fedora', operatingsystemmajrelease: ['30']

  confine feature: :augeas
  confine augeasprovider_grub_blscfg: true
  defaultfor augeasprovider_grub_blscfg: true

  # when both grub* providers match, prefer GRUB 2
  def self.specificity
    super + 1
  end

  def self.instances
    augopen do |aug|
      resources = []

      #   Grubenv.lns := aug.match("$target/*[name = 'kernelopts']/value").map
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]

      params.keys.sort.each do |param|
        params[param] = params[param][0] if params[param].length == 1
        param = {
          ensure: :present,
          name: param,
          value: params[param],
          bootmode: 'default'
        }
        resources << new(param)
      end
      resources
    end
  end

  def self.section(resource)
    case resource[:bootmode].to_s
    when 'all', 'default', 'normal'
      # Can we be sure every kernel is using $kernelopts?
      # BLS doesn't have 'recovery' mode
      'kernelopts'
    else
      raise("Unsupported bootmode for #{self.class} provider")
    end
  end

  def create
    self.value = resource[:value]
  end

  def destroy
    augopen do |aug|
      opts = ''
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]

      if resource[:value].nil?
        params.delete(resource[:name])
      else
        resource[:value].each do |val|
          params[resource[:name]].delete(val)
        end
      end

      params.each do |param, values|
        values.each do |value|
          opts << if value.nil?
                    "#{param} "
                  else
                    "#{param}=#{value} "
                  end
        end
      end
      aug.set('$target/kernelopts', opts)
    end
  end

  def exists?
    augopen do |aug|
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]
      params[@property_hash[:name]] || false
    end
  end

  def insync?
    augopen do |aug|
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]
      params[@property_hash[:name]] == @property_hash[:value]
    end
  end

  def value
    augopen do |aug|
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]
      params[@property_hash[:name]]
    end
  end

  def value=(newval)
    augopen do |aug|
      opts = ''
      params = aug.match('$target/kernelopts').map do |pp|
                 elements = {}
                 aug.get(pp).strip.split(' ').each do |ele|
                   key_val = ele.split('=', 2)

                   value = if key_val.length < 2
                             nil
                           else
                             key_val[1]
                           end
                   if elements.key?(key_val[0])
                     elements[key_val[0]].push(value)
                   else
                     elements[key_val[0]] = [value]
                   end
                 end
                 elements
               end[0]
      params[@property_hash[:name]] = newval.clone

      params.each do |param, values|
        values.each do |value|
          opts << if value.nil?
                    "#{param} "
                  else
                    "#{param}=#{value} "
                  end
        end
      end
      aug.set('$target/kernelopts', opts)
    end
  end
end
