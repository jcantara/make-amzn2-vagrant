require 'spec_helper'

describe kernel_module('vboxguest') do
  it { is_expected.to be_loaded }
end

describe file('/etc/os-release') do
  it { is_expected.to contain 'Amazon Linux 2' }
end

describe file('/home/ec2-user/.ssh/authorized_keys') do
  it { is_expected.to be_a_file }
  it { is_expected.to contain File.read(Dir.home + '/.ssh/id_rsa.pub') }
  it { is_expected.to be_mode 600 }
end
