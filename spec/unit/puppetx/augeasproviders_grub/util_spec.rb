#!/usr/bin/env rspec
# frozen_string_literal: true

require 'rspec'
require 'puppet'
require 'facter'

# Load the main module we're testing
require 'puppetx/augeasproviders_grub/util'

util_class = PuppetX::AugeasprovidersGrub::Util

describe util_class do
  before do
    # Clear Facter facts similar to grub2_spec.rb
    Facter.clear
  end

  describe '.grub2_cfg_paths' do
    let(:paths) do
      [
        '/etc/grub2.cfg',
        '/etc/grub2-efi.cfg',
        '/boot/efi/EFI/centos/grub.cfg',
        '/boot/grub2/grub.cfg',
        '/boot/grub/grub.cfg'
      ]
    end

    before do
      # Mock os_name to return 'centos' for predictable path generation
      allow(described_class).to receive(:os_name).and_return('centos')

      # Reset all file system checks
      allow(File).to receive(:readable?).and_return(false)
      allow(File).to receive(:directory?).and_return(false)
      allow(File).to receive(:realpath).and_call_original
      allow(File).to receive(:foreach).and_call_original
    end

    context 'when no grub config files exist' do
      it 'raises an error' do
        expect { described_class.grub2_cfg_paths }.to raise_error(
          RuntimeError,
          %r{No grub configuration found at}
        )
      end
    end

    context 'when grub config files exist' do
      before do
        allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
        allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/etc/grub2.cfg')
      end

      context 'and contains regular grub configuration' do
        before do
          # Mock file content without configfile directive
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# GRUB2 configuration file').
            and_yield('set timeout=5').
            and_yield('menuentry "Linux" {').
            and_yield('  linux /vmlinuz').
            and_yield('}')
        end

        it 'returns the valid config path' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'and contains stub configuration with configfile directive' do
        before do
          # Mock file content with configfile directive (Debian-style stub)
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# GRUB2 stub configuration').
            and_yield('set prefix=/boot/grub').
            and_yield('configfile /boot/grub/grub.cfg')
        end

        it 'excludes the stub file and raises error when no other files exist' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end

      context 'and contains configfile directive at start of line' do
        before do
          # Mock file content with configfile directive at start of line
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# GRUB2 stub').
            and_yield('configfile /boot/grub/grub.cfg')
        end

        it 'excludes the stub file when configfile is at start of line' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end
    end

    context 'when multiple grub config files exist' do
      before do
        # Mock multiple files as readable
        allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
        allow(File).to receive(:readable?).with('/boot/grub2/grub.cfg').and_return(true)
        allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/etc/grub2.cfg')
        allow(File).to receive(:realpath).with('/boot/grub2/grub.cfg').and_return('/boot/grub2/grub.cfg')
      end

      context 'with one stub and one regular config' do
        before do
          # First file is a stub
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('configfile /boot/grub/grub.cfg')

          # Second file is regular config
          allow(File).to receive(:foreach).with('/boot/grub2/grub.cfg').and_yield('# Regular GRUB config').
            and_yield('menuentry "Linux" {}')
        end

        it 'returns only the non-stub config' do
          expect(described_class.grub2_cfg_paths).to eq(['/boot/grub2/grub.cfg'])
        end
      end

      context 'with multiple regular configs' do
        before do
          # Both files are regular configs
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# Regular GRUB config').
            and_yield('menuentry "Linux" {}')

          allow(File).to receive(:foreach).with('/boot/grub2/grub.cfg').and_yield('# Another regular config').
            and_yield('set timeout=10')
        end

        it 'returns both configs' do
          result = described_class.grub2_cfg_paths
          expect(result).to include('/etc/grub2.cfg')
          expect(result).to include('/boot/grub2/grub.cfg')
          expect(result.length).to eq(2)
        end
      end

      context 'with symlinked files' do
        before do
          allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
          allow(File).to receive(:readable?).with('/etc/grub2-efi.cfg').and_return(true)

          # Both symlink to the same real file
          allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/boot/grub2/grub.cfg')
          allow(File).to receive(:realpath).with('/etc/grub2-efi.cfg').and_return('/boot/grub2/grub.cfg')

          allow(File).to receive(:foreach).with('/boot/grub2/grub.cfg').and_yield('# Real config').
            and_yield('menuentry "Linux" {}')
        end

        it 'returns unique paths only' do
          expect(described_class.grub2_cfg_paths).to eq(['/boot/grub2/grub.cfg'])
        end
      end
    end

    context 'when checking file readability and type' do
      before do
        allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/etc/grub2.cfg')
      end

      context 'when file is not readable' do
        before do
          allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(false)
        end

        it 'skips the file' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end

      context 'when path is a directory' do
        before do
          allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
          allow(File).to receive(:directory?).with('/etc/grub2.cfg').and_return(true)
        end

        it 'skips the directory' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end
    end

    context 'with Debian-style configuration scenario' do
      before do
        # Simulate typical Debian setup where /etc/grub2.cfg is a stub
        # and /boot/grub/grub.cfg contains the real configuration
        allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
        allow(File).to receive(:readable?).with('/boot/grub/grub.cfg').and_return(true)
        allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/etc/grub2.cfg')
        allow(File).to receive(:realpath).with('/boot/grub/grub.cfg').and_return('/boot/grub/grub.cfg')

        # /etc/grub2.cfg is a stub file
        allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# Stub file pointing to real config').
          and_yield('search --no-floppy --fs-uuid --set=root abcd-efgh').
          and_yield('configfile ($root)/boot/grub/grub.cfg')

        # /boot/grub/grub.cfg is the real config
        allow(File).to receive(:foreach).with('/boot/grub/grub.cfg').and_yield('# This file provides configuration for GRUB').
          and_yield('set timeout=5').
          and_yield('menuentry "Debian GNU/Linux" {').
          and_yield('  linux /vmlinuz root=/dev/sda1').
          and_yield('}')
      end

      it 'correctly identifies and uses the real config file' do
        expect(described_class.grub2_cfg_paths).to eq(['/boot/grub/grub.cfg'])
      end
    end

    context 'with edge case configfile patterns' do
      before do
        allow(File).to receive(:readable?).with('/etc/grub2.cfg').and_return(true)
        allow(File).to receive(:realpath).with('/etc/grub2.cfg').and_return('/etc/grub2.cfg')
      end

      context 'when configfile appears in a comment' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# This file uses configfile directive').
            and_yield('set timeout=5').
            and_yield('menuentry "Test" {}')
        end

        it 'does not exclude the file' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile appears at start of line only' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield('  # not configfile at start').
            and_yield('echo "configfile mentioned here"').
            and_yield('configfile /real/config')
        end

        it 'excludes the file when configfile is at line start' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end

      context 'when configfile appears with leading whitespace' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield('  # leading spaces example').
            and_yield('  configfile /real/config')
        end

        it 'includes the file when configfile has leading whitespace (not detected as stub)' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile appears with tabs' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield("\tconfigfile /real/config")
        end

        it 'includes the file when configfile has leading tabs (not detected as stub)' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile appears with mixed whitespace' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield(" \t configfile\t/real/config")
        end

        it 'includes the file when configfile has mixed whitespace (not detected as stub)' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when file is empty' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg')
        end

        it 'includes the empty file as valid' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when file contains only comments' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# This is a comment').
            and_yield('# Another comment').
            and_yield('# configfile is mentioned here but in comment')
        end

        it 'includes the file as valid when configfile only appears in comments' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile is part of another command' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield('echo "Using configfile command"').
            and_yield('load_configfile_module')
        end

        it 'includes the file when configfile is not at start of line' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile has different capitalization' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set root=hd0,1').
            and_yield('ConfigFile /real/config').
            and_yield('CONFIGFILE /another/config')
        end

        it 'includes the file when configfile has different case (case-sensitive match)' do
          expect(described_class.grub2_cfg_paths).to eq(['/etc/grub2.cfg'])
        end
      end

      context 'when configfile is the only content' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('configfile /boot/grub/grub.cfg')
        end

        it 'excludes the file when configfile is the only line' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end

      context 'when multiple configfile directives exist' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('# Stub file').
            and_yield('configfile /boot/grub/grub.cfg').
            and_yield('configfile /another/grub.cfg')
        end

        it 'excludes the file on first configfile match' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end

      context 'when configfile has various arguments' do
        before do
          allow(File).to receive(:foreach).with('/etc/grub2.cfg').and_yield('set prefix=/boot/grub').
            and_yield('configfile ($root)/boot/grub/grub.cfg')
        end

        it 'excludes the file when configfile has complex arguments' do
          expect { described_class.grub2_cfg_paths }.to raise_error(
            RuntimeError,
            %r{No grub configuration found at}
          )
        end
      end
    end

    context 'with different operating system names' do
      before do
        allow(File).to receive(:readable?).and_return(false)
        allow(File).to receive(:directory?).and_return(false)
      end

      context 'when os_name returns Ubuntu' do
        before do
          allow(described_class).to receive(:os_name).and_return('Ubuntu')
          allow(File).to receive(:readable?).with('/boot/efi/EFI/ubuntu/grub.cfg').and_return(true)
          allow(File).to receive(:realpath).with('/boot/efi/EFI/ubuntu/grub.cfg').and_return('/boot/efi/EFI/ubuntu/grub.cfg')
          allow(File).to receive(:foreach).with('/boot/efi/EFI/ubuntu/grub.cfg').and_yield('# Ubuntu GRUB config').
            and_yield('menuentry "Ubuntu" {}')
        end

        it 'includes the Ubuntu-specific EFI path' do
          expect(described_class.grub2_cfg_paths).to eq(['/boot/efi/EFI/ubuntu/grub.cfg'])
        end
      end

      context 'when os_name returns empty string' do
        before do
          allow(described_class).to receive(:os_name).and_return('')
          allow(File).to receive(:readable?).with('/boot/efi/EFI//grub.cfg').and_return(true)
          allow(File).to receive(:realpath).with('/boot/efi/EFI//grub.cfg').and_return('/boot/efi/EFI//grub.cfg')
          allow(File).to receive(:foreach).with('/boot/efi/EFI//grub.cfg').and_yield('# Generic EFI config').
            and_yield('menuentry "Linux" {}')
        end

        it 'includes the path with empty OS name' do
          expect(described_class.grub2_cfg_paths).to eq(['/boot/efi/EFI//grub.cfg'])
        end
      end
    end
  end

  describe '.grub2_cfg_path' do
    context 'when grub2_cfg_paths returns multiple paths' do
      before do
        allow(described_class).to receive(:grub2_cfg_paths).and_return([
                                                                         '/etc/grub2.cfg',
                                                                         '/boot/grub2/grub.cfg'
                                                                       ])
      end

      it 'returns the first path' do
        expect(described_class.grub2_cfg_path).to eq('/etc/grub2.cfg')
      end
    end

    context 'when grub2_cfg_paths returns empty array' do
      before do
        allow(described_class).to receive(:grub2_cfg_paths).and_return([])
      end

      it 'raises an error' do
        expect { described_class.grub2_cfg_path }.to raise_error(
          Puppet::Error,
          'Could not find a GRUB2 configuration on the system'
        )
      end
    end
  end

  describe '.munge_options' do
    # Include some basic tests for the existing functionality to ensure no regression
    it 'handles basic option merging' do
      system_opts = %w[quiet splash]
      new_opts = ['debug']

      result = described_class.munge_options(system_opts, new_opts)
      expect(result).to include('debug')
    end

    it 'handles :preserve: option' do
      system_opts = %w[quiet splash]
      new_opts = [':preserve:', 'debug']

      result = described_class.munge_options(system_opts, new_opts)
      expect(result).to include('quiet', 'splash', 'debug')
    end

    it 'handles :defaults: option' do
      system_opts = %w[quiet splash]
      new_opts = [':defaults:', 'debug']
      default_opts = ['console=tty0']

      result = described_class.munge_options(system_opts, new_opts, default_opts)
      expect(result).to include('console=tty0', 'debug')
    end
  end

  describe '.os_name' do
    context 'when modern Facter is available' do
      before do
        allow(Facter).to receive(:value).with(:os).and_return({ 'name' => 'CentOS' })
      end

      it 'returns the OS name from modern fact' do
        expect(described_class.os_name).to eq('CentOS')
      end
    end

    context 'when legacy Facter is available' do
      before do
        allow(Facter).to receive(:value).with(:os).and_return(nil)
        allow(Facter).to receive(:value).with(:operatingsystem).and_return('Ubuntu')
      end

      it 'returns the OS name from legacy fact' do
        expect(described_class.os_name).to eq('Ubuntu')
      end
    end

    context 'when no OS facts are available' do
      before do
        allow(Facter).to receive(:value).with(:os).and_return(nil)
        allow(Facter).to receive(:value).with(:operatingsystem).and_return(nil)
      end

      it 'returns empty string as fallback' do
        expect(described_class.os_name).to eq('')
      end
    end
  end
end
