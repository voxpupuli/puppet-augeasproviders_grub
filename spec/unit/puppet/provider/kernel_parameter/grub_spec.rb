#!/usr/bin/env rspec
# frozen_string_literal: true

require 'spec_helper'

provider_class = Puppet::Type.type(:kernel_parameter).provider(:grub)

describe provider_class do
  before do
    Facter.clear
    allow(Facter).to receive(:fact).with(:augeasprovider_grub_version).and_return(Facter.add(:augeasprovider_grub_version) { setcode { 1 } })

    allow(provider_class).to receive(:default?).and_return(true)
    allow(FileTest).to receive(:exist?).and_return(false)
    allow(FileTest).to receive(:executable?).and_return(false)
    allow(FileTest).to receive(:exist?).with('/boot/grub/menu.lst').and_return(true)
  end

  describe 'when finding GRUB config' do
    it 'finds EFI config when present' do
      allow(FileTest).to receive(:exist?).with('/boot/efi/EFI/redhat/grub.conf').and_return(true)
      expect(provider_class.target).to eq '/boot/efi/EFI/redhat/grub.conf'
    end

    it 'defaults to BIOS config' do
      allow(FileTest).to receive(:exist?).with('/boot/efi/EFI/redhat/grub.conf').and_return(false)
      expect(provider_class.target).to eq '/boot/grub/menu.lst'
    end
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

      expect(inst.size).to eq 10
      expect(inst[0]).to include(name: 'ro', ensure: :present, value: :absent, bootmode: :all)
      expect(inst[1]).to include(name: 'root', ensure: :present, value: '/dev/VolGroup00/LogVol00', bootmode: :all)
      expect(inst[2]).to include(name: 'rhgb', ensure: :present, value: :absent, bootmode: :default)
      expect(inst[3]).to include(name: 'quiet', ensure: :present, value: :absent, bootmode: :default)
      expect(inst[4]).to include(name: 'elevator', ensure: :present, value: 'noop', bootmode: :all)
      expect(inst[5]).to include(name: 'divider', ensure: :present, value: '10', bootmode: :all)
      expect(inst[6]).to include(name: 'rd_LVM_LV', ensure: :present, value: ['vg/lv1', 'vg/lv2'], bootmode: :default)
      expect(inst[7]).to include(name: 'S', ensure: :present, value: :absent, bootmode: :recovery)
      expect(inst[8]).to include(name: 'splash', ensure: :present, value: :absent, bootmode: :normal)
      expect(inst[9]).to include(name: 'nohz', ensure: :present, value: 'on', bootmode: :normal)
    end

    describe 'when creating entries' do
      it 'creates no-value entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 3
          expect(aug.match('title/kernel/foo').map { |p| aug.get(p) }).to eq [nil] * 3
        end
      end

      it 'creates entry with value' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: 'bar',
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 3
          expect(aug.match('title/kernel/foo').map { |p| aug.get(p) }).to eq ['bar'] * 3
        end
      end

      it 'creates entries with multiple values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 value: %w[bar baz],
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 6
          expect(aug.match('title/kernel/foo').map { |p| aug.get(p) }).to eq %w[bar baz] * 3
        end
      end

      # This is a "create" because rd_LVM_LV only exists on one entry in the
      # fixture.  If it was on all, it would be a modification.
      it 'changes existing values if present' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'rd_LVM_LV',
                 ensure: :present,
                 value: ['vg/lv7', 'vg/lv8', 'vg/lv9'],
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/rd_LVM_LV').size).to eq 9
          expect(aug.match("title/kernel/rd_LVM_LV[.='vg/lv1']").size).to eq 0
          expect(aug.match("title/kernel/rd_LVM_LV[.='vg/lv2']").size).to eq 0
          expect(aug.match('title/kernel/rd_LVM_LV').map { |p| aug.get(p) }).to eq ['vg/lv7', 'vg/lv8', 'vg/lv9'] * 3
        end
      end

      it 'removes existing values if too many' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'rd_LVM_LV',
                 ensure: :present,
                 value: ['vg/lv7'],
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/rd_LVM_LV').size).to eq 3
          expect(aug.match("title/kernel/rd_LVM_LV[.='vg/lv1']").size).to eq 0
          expect(aug.match("title/kernel/rd_LVM_LV[.='vg/lv2']").size).to eq 0
          expect(aug.match('title/kernel/rd_LVM_LV').map { |p| aug.get(p) }).to eq ['vg/lv7'] * 3
        end
      end

      it 'creates default-only entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 bootmode: :default,
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 1
          expect(aug.match('title[int(../default)+1]/kernel/foo').size).to eq 1
        end
      end

      it 'creates recovery-only entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 bootmode: :recovery,
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 1
          expect(aug.match('title[2]/kernel/foo').size).to eq 1
        end
      end

      it 'creates normal boot-only entries' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'foo',
                 ensure: :present,
                 bootmode: :normal,
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/foo').size).to eq 2
          expect(aug.match('title[1]/kernel/foo').size).to eq 1
          expect(aug.match('title[3]/kernel/foo').size).to eq 1
        end
      end
    end

    describe 'when deleting entries' do
      it 'deletes entries when present on all resources' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'divider',
                 ensure: 'absent',
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/divider')).to eq []
        end
      end

      # rd_LVM_LV only exists on one entry in the fixture
      it 'deletes entries if partially present' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'rd_LVM_LV',
                 ensure: :absent,
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/rd_LVM_LV').size).to eq 0
        end
      end
    end

    describe 'when modifying values' do
      before do
        allow_any_instance_of(provider_class).to receive(:create).and_raise('nope')
      end

      it 'changes existing values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: 'deadline',
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/elevator').size).to eq 3
          expect(aug.match('title/kernel/elevator').map { |p| aug.get(p) }).to eq ['deadline'] * 3
        end
      end

      it 'adds value to entry' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'ro',
                 ensure: :present,
                 value: 'foo',
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/ro').size).to eq 3
          expect(aug.match('title/kernel/ro').map { |p| aug.get(p) }).to eq ['foo'] * 3
        end
      end

      it 'adds entries for multiple values' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'elevator',
                 ensure: :present,
                 value: %w[noop deadline],
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/elevator').size).to eq 6
          expect(aug.match('title/kernel/elevator').map { |p| aug.get(p) }).to eq %w[noop deadline] * 3
        end
      end

      it 'changes existing values if present' do
        apply!(Puppet::Type.type(:kernel_parameter).new(
                 name: 'root',
                 ensure: :present,
                 value: %w[test1 test2],
                 target: target,
                 provider: 'grub'
               ))

        aug_open(target, 'Grub.lns') do |aug|
          expect(aug.match('title/kernel/root').size).to eq 6
          expect(aug.match("title/kernel/root[.='/dev/VolGroup00/LogVol00']").size).to eq 0
          expect(aug.match('title/kernel/root').map { |p| aug.get(p) }).to eq %w[test1 test2] * 3
        end
      end
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
                    provider: 'grub'
                  ))

      expect(txn.any_failed?).not_to eq nil
      expect(@logs.first.level).to eq :err
      expect(@logs.first.message.include?(target)).to eq true
    end
  end
end
