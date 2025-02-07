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
                sh """
                echo "Installing Terraform v${TERRAFORM_VERSION}..."
                sudo apt-get update -y
                sudo apt-get install -y wget unzip
                wget -q https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
                sudo unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin/
                rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
                terraform --version
                """
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
