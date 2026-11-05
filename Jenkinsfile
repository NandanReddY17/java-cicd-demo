// Jenkins CI/CD pipeline: GitHub -> Maven -> Docker -> (Amazon ECR -> Amazon EKS via Ansible)
// The AWS stages run only when the Jenkins global env var AWS_DEPLOY is "true"
// and a credential with ID "aws-creds" exists (username = access key ID, password = secret key).
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()          // never two deployments at once
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    triggers {
        // Jenkins runs on a local PC that GitHub cannot reach, so it polls GitHub
        // every minute instead of waiting for a webhook.
        pollSCM('* * * * *')
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        EKS_CLUSTER    = 'java-cicd-cluster'
        ECR_REPOSITORY = 'java-cicd-demo'
        APP_NAME       = 'java-cicd-demo'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_SHA = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.LOCAL_IMAGE = "${env.APP_NAME}:${env.GIT_SHA}"
                }
                echo "Building commit ${env.GIT_SHA}"
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn -B compile'
            }
        }

        stage('Unit Tests') {
            steps {
                sh 'mvn -B test'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
            }
        }

        stage('Package') {
            steps {
                sh 'mvn -B -DskipTests package'
                archiveArtifacts artifacts: 'target/java-cicd-demo.jar', fingerprint: true
            }
        }

        stage('Docker Build') {
            steps {
                sh 'docker build -t "$LOCAL_IMAGE" -t "$APP_NAME:latest" .'
            }
        }

        stage('Container Smoke Test') {
            // Start the new image and call it over HTTP before it goes anywhere near the cluster.
            steps {
                sh '''
                    NET="smoke-$BUILD_NUMBER"
                    docker network create "$NET" >/dev/null
                    docker run -d --name "smoke-$BUILD_NUMBER" --network "$NET" \
                      -e APP_BUILD="$GIT_SHA" "$LOCAL_IMAGE" >/dev/null
                    for i in $(seq 1 30); do
                      if docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                           "http://smoke-$BUILD_NUMBER:8080/actuator/health/readiness" >/dev/null 2>&1; then
                        break
                      fi
                      sleep 2
                    done
                    docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                      "http://smoke-$BUILD_NUMBER:8080/api/calculate?a=6&b=7&op=multiply" | tee smoke.json
                    grep -q '"result":42.0' smoke.json
                    docker run --rm --network "$NET" curlimages/curl:8.11.1 -sf \
                      "http://smoke-$BUILD_NUMBER:8080/api/info" | grep -q "\\"build\\":\\"$GIT_SHA\\""
                    echo "Smoke test passed"
                '''
            }
            post {
                always {
                    sh 'docker rm -f "smoke-$BUILD_NUMBER" >/dev/null 2>&1 || true; docker network rm "smoke-$BUILD_NUMBER" >/dev/null 2>&1 || true'
                }
            }
        }

        stage('Push to Amazon ECR') {
            when { environment name: 'AWS_DEPLOY', value: 'true' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        set +x
                        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
                        REGISTRY="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
                        aws ecr get-login-password --region "$AWS_REGION" | docker login -u AWS --password-stdin "$REGISTRY"
                        docker tag "$LOCAL_IMAGE" "$REGISTRY/$ECR_REPOSITORY:$GIT_SHA"
                        docker tag "$LOCAL_IMAGE" "$REGISTRY/$ECR_REPOSITORY:latest"
                        docker push "$REGISTRY/$ECR_REPOSITORY:$GIT_SHA"
                        docker push "$REGISTRY/$ECR_REPOSITORY:latest"
                        docker logout "$REGISTRY"
                        echo "$REGISTRY/$ECR_REPOSITORY:$GIT_SHA" > image.txt
                    '''
                }
            }
        }

        stage('Deploy to EKS (Ansible)') {
            when { environment name: 'AWS_DEPLOY', value: 'true' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        export KUBECONFIG="$WORKSPACE/.kubeconfig"
                        aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$AWS_REGION"
                        ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                          -e image="$(cat image.txt)" -e build="$GIT_SHA"
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            when { environment name: 'AWS_DEPLOY', value: 'true' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        export KUBECONFIG="$WORKSPACE/.kubeconfig"
                        kubectl get deployment "$APP_NAME"
                        kubectl get pods -l app="$APP_NAME" -o wide
                        kubectl get service "$APP_NAME"
                        kubectl rollout history deployment/"$APP_NAME"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline succeeded for commit ${env.GIT_SHA}"
        }
        failure {
            echo 'Pipeline failed. Check the red stage in the Stage View for details.'
        }
        always {
            sh 'rm -f .kubeconfig'
        }
    }
}
