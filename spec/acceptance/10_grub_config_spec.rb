# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

describe 'Global Config Tests' do
  hosts.each do |host|
    context 'set timeout' do
      let(:manifest) do
        %(
        grub_config { 'GRUB_TIMEOUT':
          value => 1
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has a timeout of 1' do
        on(host, %(grep 'GRUB_TIMEOUT="\\?1"\\?' /etc/default/grub))
        on(host, %(grep 'timeout=1' /boot/grub2/grub.cfg))
      end
    end

    context 'set arbitrary value' do
      let(:manifest) do
        %(
        grub_config { 'GRUB_FOOBAR':
          value => 'BAZ'
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has a GRUB_FOOBAR of BAZ' do
        on(host, %(grep 'GRUB_FOOBAR="BAZ"' /etc/default/grub))
      end
    end

    context 'remove value' do
      let(:manifest) do
        %(
        grub_config { 'GRUB_FOOBAR':
          ensure => 'absent'
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'does not have a GRUB_FOOBAR' do
        on(host, %(grep "GRUB_FOOBAR" /etc/default/grub), acceptable_exit_codes: [1])
      end
    end

    context 'set Boolean value' do
      let(:manifest) do
        %(
        grub_config { 'GRUB_BOOLEAN_TEST':
          value => true
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has a GRUB_BOOLEAN_TEST that is true' do
        on(host, %(grep 'GRUB_BOOLEAN_TEST="true"' /etc/default/grub))
      end
    end

    context 'set a value with spaces' do
      let(:manifest) do
        %(
        grub_config { 'GRUB_SPACES_TEST':
          value => 'this thing -has --spaces'
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has a valid GRUB_SPACES_TEST entry' do
        on(host, %(grep 'GRUB_SPACES_TEST="this thing -has --spaces"' /etc/default/grub))
      end
    end
  end
end
