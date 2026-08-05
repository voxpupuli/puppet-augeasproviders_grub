#!/usr/bin/env rspec
# frozen_string_literal: true

require 'spec_helper'

LENS = 'Shellvars_list.lns'
FILTER = "*[label() =~ regexp('GRUB_CMDLINE_LINUX.*')]"

describe Puppet::Type.type(:kernel_parameter).provider(:grub2) do
  let(:provider_class) { Puppet::Type.type(:kernel_parameter).provider(:grub2) }

  it 'finds grub2-mkconfig' do
    allow(FileTest).to receive_messages(file?: false, executable?: false)
    allow(FileTest).to receive(:file?).with('/usr/sbin/grub2-mkconfig').and_return(true)
    allow(FileTest).to receive(:executable?).with('/usr/sbin/grub2-mkconfig').and_return(true)
    expect(provider_class.mkconfig_path).to eq '/usr/sbin/grub2-mkconfig'
  end

  it 'finds grub-mkconfig' do
    allow(FileTest).to receive_messages(file?: false, executable?: false)
    allow(FileTest).to receive(:file?).with('/usr/sbin/grub-mkconfig').and_return(true)
    allow(FileTest).to receive(:executable?).with('/usr/sbin/grub-mkconfig').and_return(true)
    expect(provider_class.mkconfig_path).to eq '/usr/sbin/grub-mkconfig'
  end

  describe 'mkconfig_cmdline' do
    before do
      allow(FileTest).to receive_messages(file?: false, executable?: false)
      allow(FileTest).to receive(:file?).with('/usr/sbin/grub2-mkconfig').and_return(true)
      allow(FileTest).to receive(:executable?).with('/usr/sbin/grub2-mkconfig').and_return(true)
    end

    {
      'RHEL 9.2' => [{ 'family' => 'RedHat', 'name' => 'RedHat', 'release' => { 'major' => '9', 'minor' => '2' } }, false],
      'RHEL 9.3' => [{ 'family' => 'RedHat', 'name' => 'RedHat', 'release' => { 'major' => '9', 'minor' => '3' } }, true],
      'RHEL 10' => [{ 'family' => 'RedHat', 'name' => 'RedHat', 'release' => { 'major' => '10', 'minor' => '0' } }, true],
      'Amazon Linux 2023' => [{ 'family' => 'RedHat', 'name' => 'Amazon', 'release' => { 'major' => '2023', 'minor' => '0' } }, false],
      'Fedora 42' => [{ 'family' => 'RedHat', 'name' => 'Fedora', 'release' => { 'major' => '42', 'minor' => '0' } }, false],
      'Debian 12' => [{ 'family' => 'Debian', 'name' => 'Debian', 'release' => { 'major' => '12', 'minor' => '0' } }, false],
    }.each do |os_desc, (os_fact, expected)|
      it "#{expected ? 'passes' : 'omits'} --update-bls-cmdline on #{os_desc}" do
        allow(Facter).to receive(:value).with(:os).and_return(os_fact)
        expected_cmdline = ['/usr/sbin/grub2-mkconfig']
        expected_cmdline << '--update-bls-cmdline' if expected
        expect(provider_class.mkconfig_cmdline).to eq expected_cmdline
      end
    end
  end
end

describe Puppet::Type.type(:kernel_parameter).provider(:grub2) do
  let(:provider_class) { Puppet::Type.type(:kernel_parameter).provider(:grub2) }

  before do
    allow_any_instance_of(provider_class).to receive(:default?).and_return(true)
    allow(FileTest).to receive_messages(exist?: false, file?: false, executable?: false)
    ['/usr/sbin/grub2-mkconfig', '/usr/sbin/grub-mkconfig'].each do |path|
      allow(FileTest).to receive(:file?).with(path).and_return(true)
      allow(FileTest).to receive(:exist?).with(path).and_return(true)
      allow(FileTest).to receive(:executable?).with(path).and_return(true)
    end
    allow(FileTest).to receive(:file?).with('/etc/grub2-efi.cfg').and_return(true)
    allow(FileTest).to receive(:file?).with('/boot/grub2/grub.cfg').and_return(true)
    allow(FileTest).to receive(:exist?).with('/etc/default/grub').and_return(true)

    require 'puppetx/augeasproviders_grub/util'
    allow(PuppetX::AugeasprovidersGrub::Util).to receive(:grub2_cfg_paths).and_return(['/dev/null'])
  end

  context 'with full file' do
    let(:tmptarget) { aug_fixture('full') }
    let(:target) { tmptarget.path }

    it 'lists instances' do
      allow(provider_class).to receive(:target).and_return(target)
      inst = provider_class.instances.map do |p|
        {
          name: p.get(:name),
          ensure: p.get(:ensure),
          value: p.get(:value),
          bootmode: p.get(:bootmode),
        }
      end

      expect(inst.size).to eq 5
      expect(inst[0]).to include(name: 'quiet', ensure: :present, value: :absent, bootmode: 'all')
      expect(inst[1]).to include(name: 'elevator', ensure: :present, value: 'noop', bootmode: 'all')
      expect(inst[2]).to include(name: 'divider', ensure: :present, value: '10', bootmode: 'all')
      expect(inst[3]).to include(name: 'rhgb', ensure: :present, value: :absent, bootmode: 'default')
      expect(inst[4]).to include(name: 'nohz', ensure: :present, value: 'on', bootmode: 'default')
    end

    describe 'when creating entries' do
      before do
        allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')
      end

      it 'creates no-value entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
            { "value" = "foo" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end

      it 'creates entry with value' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: 'bar',
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
            { "value" = "foo=bar" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end

      it 'creates entries with multiple values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: %w[bar baz],
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
            { "value" = "foo=bar" }
            { "value" = "foo=baz" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end

      it 'creates normal boot-only entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 bootmode: :normal,
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
            { "value" = "foo" }
          }
        ')
      end

      it 'creates default boot-only entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 bootmode: :default,
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
            { "value" = "foo" }
          }
        ')
      end
    end

    it 'errors on recovery-only entries' do
      txn = apply(Puppet::Type.type(:kernel_parameter).new(
                    name: 'foo',
                    ensure: :present,
                    bootmode: :recovery,
                    target: target,
                    provider: 'grub2',
                  ))

      expect(txn.any_failed?).not_to eq nil
      expect(@logs.first.level).to eq :err
      expect(@logs.first.message.include?('Unsupported bootmode')).to eq true
    end

    it 'deletes entries' do
      allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')

      apply!(Puppet::Type.type(:kernel_parameter).new(
               name: 'divider',
               ensure: 'absent',
               target: target,
               provider: 'grub2',
             ))

      augparse_filter(target, LENS, FILTER, '
        { "GRUB_CMDLINE_LINUX"
          { "quote" = "\"" }
          { "value" = "quiet" }
          { "value" = "elevator=noop" }
        }
        { "GRUB_CMDLINE_LINUX_DEFAULT"
          { "quote" = "\"" }
          { "value" = "rhgb" }
          { "value" = "nohz=on" }
        }
      ')
    end

    it 'deletes specific entries' do
      allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')

      apply!(Puppet::Type.type(:kernel_parameter).new(
               title: 'rhgb:normal',
               ensure: 'absent',
               target: target,
               provider: 'grub2',
             ))

      augparse_filter(target, LENS, FILTER, '
        { "GRUB_CMDLINE_LINUX"
          { "quote" = "\"" }
          { "value" = "quiet" }
          { "value" = "elevator=noop" }
          { "value" = "divider=10" }
        }
        { "GRUB_CMDLINE_LINUX_DEFAULT"
          { "quote" = "\"" }
          { "value" = "nohz=on" }
        }
      ')
    end

    it 'creates specific entries' do
      allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')

      apply!(Puppet::Type.type(:kernel_parameter).new(
               title: 'splash:default',
               ensure: 'present',
               target: target,
               provider: 'grub2',
             ))

      augparse_filter(target, LENS, FILTER, '
        { "GRUB_CMDLINE_LINUX"
          { "quote" = "\"" }
          { "value" = "quiet" }
          { "value" = "elevator=noop" }
          { "value" = "divider=10" }
        }
        { "GRUB_CMDLINE_LINUX_DEFAULT"
          { "quote" = "\"" }
          { "value" = "rhgb" }
          { "value" = "nohz=on" }
          { "value" = "splash" }
        }
      ')
    end

    describe 'when modifying values' do
      before do
        allow_any_instance_of(provider_class).to receive(:create).and_raise('nope')
      end

      it 'changes existing values' do
        allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: 'deadline',
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=deadline" }
            { "value" = "divider=10" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end

      it 'adds value to entry' do
        allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'quiet',
                 ensure: :present,
                 value: 'foo',
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet=foo" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end

      it 'adds and remove entries for multiple values' do
        # This will run once for each parameter resource
        allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')

        # Add multiple entries
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: %w[noop deadline],
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=noop" }
            { "value" = "divider=10" }
            { "value" = "elevator=deadline" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')

        # Remove one excess entry
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: ['deadline'],
                 target: target,
                 provider: 'grub2',
               ))

        augparse_filter(target, LENS, FILTER, '
          { "GRUB_CMDLINE_LINUX"
            { "quote" = "\"" }
            { "value" = "quiet" }
            { "value" = "elevator=deadline" }
            { "value" = "divider=10" }
          }
          { "GRUB_CMDLINE_LINUX_DEFAULT"
            { "quote" = "\"" }
            { "value" = "rhgb" }
            { "value" = "nohz=on" }
          }
        ')
      end
    end
  end

  describe 'name_match' do
    {
      'quiet' => "[.=~regexp('^quiet(=.*)?$')]",
      'ipv6.enable' => "[.=~regexp('^ipv6[.]enable(=.*)?$')]",
      'a.b.c' => "[.=~regexp('^a[.]b[.]c(=.*)?$')]",
    }.each do |name, expected|
      it "matches #{name.inspect} with #{expected}" do
        expect(provider_class.name_match(name)).to eq expected
      end
    end
  end

  context 'with dotted parameter names' do
    let(:tmptarget) { aug_fixture('dotted') }
    let(:target) { tmptarget.path }

    before do
      allow_any_instance_of(provider_class).to receive(:mkconfig).and_return('OK')
    end

    # instances() drives 'puppet resource' and 'resources { purge => true }', so
    # an over-matched name reports a value that belongs to a sibling parameter.
    it 'reports the value of only the exactly named parameter' do
      allow(provider_class).to receive(:target).and_return(target)
      inst = provider_class.instances.map { |p| [p.get(:name), p.get(:value)] }

      expect(inst).to include(['ipv6.enable', '1'])
      expect(inst).to include(%w[ipv6_enable 2])
      expect(inst).to include(%w[ipv6Xenable 3])
    end

    it 'changes only the exactly named parameter' do
      apply!(Puppet::Type.type(:kernel_parameter).new(
               name: 'ipv6.enable',
               ensure: :present,
               value: '9',
               target: target,
               provider: 'grub2',
             ))

      augparse_filter(target, LENS, FILTER, '
        { "GRUB_CMDLINE_LINUX"
          { "quote" = "\"" }
          { "value" = "quiet" }
          { "value" = "ipv6.enable=9" }
          { "value" = "ipv6_enable=2" }
          { "value" = "ipv6Xenable=3" }
        }
        { "GRUB_CMDLINE_LINUX_DEFAULT"
          { "quote" = "\"" }
          { "value" = "rhgb" }
          { "value" = "nohz=on" }
        }
      ')
    end

    it 'deletes only the exactly named parameter' do
      apply!(Puppet::Type.type(:kernel_parameter).new(
               name: 'ipv6.enable',
               ensure: 'absent',
               target: target,
               provider: 'grub2',
             ))

      augparse_filter(target, LENS, FILTER, '
        { "GRUB_CMDLINE_LINUX"
          { "quote" = "\"" }
          { "value" = "quiet" }
          { "value" = "ipv6_enable=2" }
          { "value" = "ipv6Xenable=3" }
        }
        { "GRUB_CMDLINE_LINUX_DEFAULT"
          { "quote" = "\"" }
          { "value" = "rhgb" }
          { "value" = "nohz=on" }
        }
      ')
    end
  end

  context 'with broken file' do
    let(:tmptarget) { aug_fixture('broken') }
    let(:target) { tmptarget.path }

    it 'fails to load' do
      txn = apply(Puppet::Type.type(:kernel_parameter).new(
                    name: 'foo',
                    ensure: :present,
                    target: target,
                    provider: 'grub2',
                  ))

      expect(txn.any_failed?).not_to eq nil
      expect(@logs.first.level).to eq :err
      expect(@logs.first.message.include?(target)).to eq true
    end
  end
end
