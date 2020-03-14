# -*- mode: ruby -*-
# vi: set ft=ruby :
require 'uri'

VAGRANFILE_API_VERSION = '2'
TOP_LEVEL_DOMAIN       = 'test'

if Vagrant::Util::Platform.windows? then
    GIT_ORIGIN_URL   = URI.parse(`git config --get remote.origin.url`.strip!).path

    projectPath         = GIT_ORIGIN_URL
    projectPath[".git"] = ""
    projectPath[0]      = ""

    GIT_PROJECT_PATH = projectPath
    GIT_BRANCH       = `git rev-parse --abbrev-ref HEAD`.downcase
    GIT_NETRC        = `for /f "tokens=2" %a in ('type \"%userprofile%\\.netrc\" ^| findstr /v "git.phoenix-media.eu"') do @echo %a`
    GIT_CREDENTIALS  = GIT_NETRC.split(/\n+/)
    GIT_USER         = GIT_CREDENTIALS[0]
    GIT_PASS         = GIT_CREDENTIALS[1]
else
    GIT_PROJECT_PATH = `echo $(bash bin/getProjectPathFromUrl.sh $(git config --get remote.origin.url))`.strip!
    GIT_BRANCH       = `echo $(git rev-parse --abbrev-ref HEAD 2> /dev/null)`.downcase
    GIT_USER         = `awk '/git.phoenix-media.eu/{getline; print $2; exit;}' $HOME/.netrc`
    GIT_PASS         = `awk '/git.phoenix-media.eu/{getline; getline; print $2; exit;}' $HOME/.netrc`
end

################################################
# We cut off the first path as its just there  #
#      for internal structuring reasons.       #
#    This is also done in the Jenkinsfile      #
#      and the bin/docker-dev.sh script !      #
################################################
project = GIT_PROJECT_PATH.tr("/", "-").split('-')[1..-1].join('-')

ENVIRONMENT    = GIT_BRANCH.tr("/", "-").tr(".", "-").strip!
PROJECT_KEY    = project.tr(".", "-") + '-' + ENVIRONMENT
PROJECT_DOMAIN = project + '-' + ENVIRONMENT + '.' + TOP_LEVEL_DOMAIN

################################################
#  Check for running centralized mail catcher  #
################################################
if Vagrant::Util::Platform.windows? then
    `dir "%userprofile%\.mail-catcher\" > nul || git clone https://git.phoenix-media.eu/vagrant/mail-catcher.git "%userprofile%\\.mail-catcher" & cd "%userprofile%\\.mail-catcher" && git pull && vagrant up`
else
    `if [ ! -d $HOME/.mail-catcher ]; then git clone https://git.phoenix-media.eu/vagrant/mail-catcher.git $HOME/.mail-catcher ; fi; cd $HOME/.mail-catcher && git pull && vagrant up`
end

################################################
#      Add variables for provisioned check     #
################################################
isBoxProvisioned = File.exists?(File.join(File.dirname(__FILE__),".vagrant/machines/default/virtualbox/action_provision"));

Vagrant.configure(VAGRANFILE_API_VERSION) do |config|

    config.vagrant.plugins = ["vagrant-hostmanager", "vagrant-vbguest"]

    ###############################################################
    #                Configure the virtual machine                #
    ###############################################################
    config.vm.provider "virtualbox" do |v|

        if (not isBoxProvisioned)
            v.name = PROJECT_KEY
        end

        v.memory = 5120
        v.cpus   = 2
        v.customize ["modifyvm", :id, "--audio", "none"]
    end

    ###############################################################
    #        We use debian in production and so we do here        #
    ###############################################################
    config.vm.box = "phoenix/k3s"
    config.vm.synced_folder ".", "/vagrant", type: "virtualbox"

    ###############################################################
    #          DNS config and create a private network,           #
    #          which allows host-only access to machine           #
    ###############################################################

    if (not isBoxProvisioned)
        config.vm.hostname = PROJECT_KEY
    end

    config.hostmanager.enabled           = false
    config.hostmanager.manage_host       = true
    config.hostmanager.ignore_private_ip = false

    config.vm.network 'private_network', type: :dhcp

    config.hostmanager.aliases = [PROJECT_DOMAIN]

    config.hostmanager.ip_resolver = proc do |vm, resolving_vm|
        vm.provider.driver.read_guest_ip(1)
    end

    ###############################################################
    #             Install Docker  and open Remote API             #
    ###############################################################
    if (not isBoxProvisioned)
        config.vm.provision "docker" do |d|
            d.post_install_provision "shell",
                inline:"sed -i 's#ExecStart=/usr/bin/dockerd#ExecStart=/usr/bin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375#' /lib/systemd/system/docker.service && systemctl daemon-reload && systemctl restart docker"
        end
    end

    ###############################################################
    #     Start the real provisioning of all needed services      #
    ###############################################################

    if (not isBoxProvisioned)
        config.vm.provision :hostmanager
    end

    provisionCommand = 'up'

    if ARGV[0] == 'reload'
        provisionCommand = 'reload'
    end

end
