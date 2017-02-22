#
# Cookbook Name:: wal-e
# Recipe:: default

# install packages
unless node[:wal_e][:packages].nil?
  node[:wal_e][:packages].each do |pkg|
    package pkg
  end
end

# install virtualenv
if node[:wal_e][:virtualenv][:enabled]
  include_recipe "wal-e::virtualenv"
end

activate = node[:wal_e][:virtualenv][:enabled] ? "#{node[:wal_e][:virtualenv][:helper]} #{node[:wal_e][:virtualenv][:activate]}" : ''
wale_bin = node[:wal_e][:virtualenv][:enabled] ? "#{node[:wal_e][:virtualenv][:path]}/bin/wal-e" : '/usr/local/bin/wal-e'
pip_user = node[:wal_e][:virtualenv][:enabled] ? node[:wal_e][:user] : node[:wal_e][:pip_user]

# install python modules with pip unless overriden
unless node[:wal_e][:pips].nil?
  include_recipe "python::pip"
  node[:wal_e][:pips].each do |pp|
    python_pip pp do
      user pip_user
      virtualenv node[:wal_e][:virtualenv][:path] if node[:wal_e][:virtualenv]
    end
  end
end

# Install from source or pip pacakge
case node[:wal_e][:install_method]
when 'source'
  code_path = "#{Chef::Config[:file_cache_path]}/wal-e"

  bash "install_wal_e" do
    cwd code_path
    code <<-EOH
      /usr/bin/python ./setup.py install
    EOH
    action :nothing
  end

  git code_path do
    repository node[:wal_e][:repository_url]
    revision node[:wal_e][:git_version]
    notifies :run, "bash[install_wal_e]"
  end
when 'pip'
  python_pip 'wal-e' do
    version node[:wal_e][:version] if node[:wal_e][:version]
    user pip_user
    virtualenv node[:wal_e][:virtualenv][:path] if node[:wal_e][:virtualenv][:enabled]
  end
end

directory node[:wal_e][:env_dir] do
  user    node[:wal_e][:user]
  group   node[:wal_e][:group]
  mode    "0550"
end

vars = {'WALE_S3_PREFIX'        => node[:wal_e][:s3_prefix] }

if node[:wal_e][:aws_access_key]
  vars['AWS_ACCESS_KEY_ID'] = node[:wal_e][:aws_access_key]
  vars['AWS_SECRET_ACCESS_KEY'] = node[:wal_e][:aws_secret_key]
  vars['AWS_REGION'] = node[:wal_e][:aws_region]
end

vars['AWS_INSTANCE_PROFILE'] = true if node[:wal_e][:use_iam_var]

vars.each do |key, value|
  file "#{node[:wal_e][:env_dir]}/#{key}" do
    content value
    user    node[:wal_e][:user]
    group   node[:wal_e][:group]
    mode    "0440"
  end
end

iam = node[:wal_e][:use_iam] ? "--aws-instance-profile" : ""

cron "wal_e_base_backup" do
  user node[:wal_e][:user]
  command "/usr/bin/envdir #{node[:wal_e][:env_dir]} #{activate} #{wale_bin} #{iam} backup-push #{node[:wal_e][:base_backup][:options]} #{node[:wal_e][:pgdata_dir]}"
  not_if { node[:wal_e][:base_backup][:disabled] }

  minute node[:wal_e][:base_backup][:minute]
  hour node[:wal_e][:base_backup][:hour]
  day node[:wal_e][:base_backup][:day]
  month node[:wal_e][:base_backup][:month]
  weekday node[:wal_e][:base_backup][:weekday]
end
