# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Augeasproviders Grub'

describe 'GRUB Menuentry Tests' do
  hosts.each do |host|
    context 'set new default kernel' do
      let(:manifest) do
        %(
        grub_menuentry { 'Standard':
          default_entry  => true,
          root           => '(hd0,msdos1)',
          kernel         => ':preserve:',
          initrd         => ':preserve:',
          kernel_options => [':preserve:', 'trogdor=BURNINATE']
        }
      )
      end

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'has set the default to the new entry' do
        result = on(host, %(grubby --info=DEFAULT)).stdout
        result_hash = {}
        result.each_line do |line|
          line =~ %r{^\s*(.*?)=(.*)\s*$}
          result_hash[Regexp.last_match(1).strip] = Regexp.last_match(2).strip
        end

        expect(result_hash['title'].delete('"')).to eq('Standard')
        expect(result_hash['args'].delete('"')).to include('trogdor=BURNINATE')
      end

      it 'activates on reboot' do
        host.reboot

        result = on(host, %(cat /proc/cmdline)).stdout
        expect(result.split(%r{\s+})).to include('trogdor=BURNINATE')
      end
    end
  end
end
