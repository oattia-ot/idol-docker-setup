# ##############################################
# Execute [source ./collect-setup-parameters.sh]
# ##############################################
**Docker Installation**
    # Update package index
    sudo apt update

	# Installing Java 
	>>>>>>> for NiFI 1 
		- $ sudo apt install openjdk-17-jdk
	>>>>>>> for NiFI 2
		- $ sudo apt install openjdk-21-jdk
		
    # Install Docker
	sudo apt update
	>>>>>>> OPTION 1
		sudo apt install docker.io 
	OR <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
	>>>>>>> OPTION 2
		sudo apt install ca-certificates curl gnupg -y
		sudo install -m 0755 -d /etc/apt/keyrings
		curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
		sudo apt update
		sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    # Enable and start Docker service
    sudo systemctl enable docker
    sudo systemctl start docker

	# Installing & Configuring Git 
		sudo apt-get install git
		git config --global user.name oattia-ot
		git config --global user.email oren.attiaa@gmail.com
		git config --list
		git config --unset-all

	# Preprqusit IDOL
		sudo mkdir -p /opt/idol
		sudo chown $USER:$USER idol/
		cd /opt/idol 
		tar -xzvf /tmp/setup-idol-v4.tar.gz 


