# frozen_string_literal: true

# Default to beaker_docker
ENV['BEAKER_HYPERVISOR'] ||= 'docker'

require 'beaker-rspec'

# Force FIPS off for these tests since it is not relevant.
ENV['BEAKER_fips'] = 'no'

require 'simp/beaker_helpers'
include Simp::BeakerHelpers

install_puppet unless ENV['BEAKER_provision'] == 'no'

RSpec.configure do |c|
  c.include Helpers

  # ensure that environment OS is ready on each host
  fix_errata_on hosts

  # Readable test descriptions
  c.formatter = :documentation

  c.before :suite do
    copy_fixture_modules_to(hosts)
  end
end
