pipeline {
    agent any // Runs on an Ubuntu agent

    environment {
        TERRAFORM_VERSION = "1.4.6" // Set Terraform version
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }
        stage('Install Terraform') {
            steps {
                script {
                    sh """
                    # Install Terraform dynamically inside Jenkins pipeline
                    sudo apt install unzip
                    curl -fsSL https://releases.hashicorp.com/terraform/1.10.5/terraform_1.10.5_linux_amd64.zip -o terraform.zip
                    unzip terraform.zip
                    sudo mv terraform /usr/local/bin/
                    rm terraform.zip
                    terraform --version
                    """
                }
            }
        }
        stage('Terraform Format Check') {
            steps {
                script {
                    def dirs = ['gcp-org', 'gcp-project-demo', 'gcp-project-dev', 'gcp-project-dns', 'modules']
                    dirs.each { dir ->
                        if (fileExists(dir)) {
                            sh "terraform fmt -check -recursive ${dir}"
                        }
                    }
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                script {
                    def dirs = ['gcp-org', 'gcp-project-demo', 'gcp-project-dev', 'gcp-project-dns']
                    dirs.each { dir ->
                        if (fileExists(dir)) {
                            sh """
                            echo "Validating Terraform configuration in ${dir}"
                            cd ${dir}
                            terraform init -backend=false
                            terraform validate
                            cd ..
                            """
                        }
                    }
                }
            }
        }
    }
}
