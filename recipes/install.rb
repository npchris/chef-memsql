#
# Cookbook Name:: memsql
# Recipe:: default
#
# Copyright 2014, Chris Molle
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



#install client libs
%w(mysql-client libmysqlclient-dev).each do |pkg|
  package pkg do
    action :install
  end
end

#download memsql
remote_file "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}" do
  source "#{node[:memsql][:url]}/#{node[:memsql][:license]}/memsql-#{node[:memsql][:version]}"
  action :create_if_missing
end

#install memsql
dpkg_package node[:memsql][:version] do
  source  "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}"
  action :install
end

#move to mounted ec2 volume
if !Dir.exists?('/data/memsql')
  %x(mv /var/lib/memsql /data/memsql)
  %x(ln -s /data/memsql /var/lib/memsql)
end

#start memsql
service "memsql" do
  supports :status => true, :restart => true, :reload => true, :start => true, :stop => true
  action [ :enable, :start ]
end

#find the master aggregator
master_aggregator = search(:node, "role:memsql_master_aggregator").first

#if there is none, assume single node installation, return self
master_aggregator = master_aggregator.nil? ? node : master_aggreagtor

#find leaf nodes
leaves = search(:node, "role:memsql_leaf")

#attaches leaf to master aggregator
leaves.each do |node|
  #Todo
  #attach the leaf on the master aggregator
  Chef::Log.info("leaf #{node["name"]} has IP address #{node["ipaddress"]}")
end


template "/var/lib/memsql/memsql.cnf" do
  source "memsql.cnf.erb"
  mode 0600
  owner "memsql"
  group "memsql"
  variables({
                :master_aggregator_ip => node.run_list.roles.include?("child_aggregator") ? master_aggregator["ipaddress"] : nil,
                :is_master => node.run_list.roles.include?("master_aggregator") ? true : false
            })
end

node[:memsql][:users].each do |user|
  %x(sudo mysql -u root -h #{master_aggregator[:ipaddress]} -e "grant all on *.* to '#{user[:name]}'@'localhost' identified by '#{user[:password]}'; flush privileges;")
end
