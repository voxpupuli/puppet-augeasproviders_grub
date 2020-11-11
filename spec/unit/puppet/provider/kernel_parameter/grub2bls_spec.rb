#!/usr/bin/env rspec

require 'spec_helper'
provider_class = Puppet::Type.type(:kernel_parameter).provider(:grub2bls)

BLSLENS = 'Simplevars.lns'
BLSFILTER = 'kernelopts'

describe provider_class do
  before :each do
    Facter.clear
    Facter.stubs(:fact).with(:augeasprovider_grub_version).returns Facter.add(:augeasprovider_grub_version) { setcode { 2 } }
    Facter.stubs(:fact).with(:augeasprovider_grub_blscfg).returns Facter.add(:augeasprovider_grub_blscfg) { setcode { true } }

    provider_class.stubs(:default?).returns(true)
  end

  context 'with full file' do
    let(:tmptarget) { aug_fixture('full') }
    let(:target) { tmptarget.path }

    it 'should list instances' do
      provider_class.stubs(:target).returns(target)
      inst = provider_class.instances.map do |p|
        {
          name: p.get(:name),
          ensure: p.get(:ensure),
          value: p.get(:value),
          bootmode: p.get(:bootmode)
        }
      end

      inst.size.should == 6
      inst[0].should == { name: 'quiet', ensure: :present, value: :absent, bootmode: 'default' }
      inst[1].should == { name: 'rd.lvm.lv', ensure: :present, bootmode: 'default', value: [
        'fedora_localhost-live/root',
        'fedora_localhost-live/swap'
      ] }
      inst[2].should == { name: 'resume', ensure: :present, value: '/dev/mapper/fedora_localhost--live-swap', bootmode: 'default' }
      inst[3].should == { name: 'rhgb', ensure: :present, value: :absent, bootmode: 'default' }
      inst[4].should == { name: 'ro', ensure: :present, value: :absent, bootmode: 'default' }
      inst[5].should == { name: 'root', ensure: :present, value: '/dev/mapper/fedora_localhost--live-root', bootmode: 'default' }

    end

    describe 'when creating entries' do
      it 'should create no-value entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet foo" }
          }
        ')
      end

      it 'should create entry with value' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: 'bar',
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet foo=bar" }
          }
        ')
      end

      it 'should create entries with multiple values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: %w[bar baz],
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet foo=bar foo=baz" }
          }
        ')
      end
    end

    it 'should error on recovery-only entries' do
      txn = apply(Puppet::Type.type(:kernel_parameter).new(
                    name: 'foo',
                    ensure: :present,
                    bootmode: :recovery,
                    target: target,
                    provider: 'grub2bls'
      ))

      txn.any_failed?.should_not.nil?
      @logs.first.level.should == :err
      @logs.first.message.include?('Unsupported bootmode').should == true
    end

    it 'should delete entries' do
      apply!(Puppet::Type.type(:kernel_parameter).new(
               name: 'rhgb',
               ensure: 'absent',
               target: target,
               provider: 'grub2bls'
      ))

      augparse_filter(target, BLSLENS, BLSFILTER, '
        { 
          { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap quiet" }
        }
      ')
    end

    describe 'when modifying values' do
      before :each do
        provider_class.any_instance.stubs(:create).never
      end

      it 'should change existing values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'root',
                 ensure: :present,
                 value: '/dev/null',
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/null ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet" }
          }
        ')
      end

      it 'should add value to entry' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'quiet',
                 ensure: :present,
                 value: 'foo',
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet=foo" }
          }
        ')
      end

      it 'should add and remove entries for multiple values' do
        # Add multiple entries
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: %w[noop deadline],
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet elevator=noop elevator=deadline" }
          }
        ')

        # Remove one excess entry
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: ['deadline'],
                 target: target,
                 provider: 'grub2bls'
        ))

        augparse_filter(target, BLSLENS, BLSFILTER, '
          { 
            { "kernelopts" = "root=/dev/mapper/fedora_localhost--live-root ro resume=/dev/mapper/fedora_localhost--live-swap rd.lvm.lv=fedora_localhost-live/root rd.lvm.lv=fedora_localhost-live/swap rhgb quiet elevator=deadline" }
          }
        ')
      end
    end
  end
end
