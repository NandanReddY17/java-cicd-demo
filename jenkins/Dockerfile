# Jenkins controller with every tool the pipeline needs:
# JDK 21 (from base image), Maven, Docker CLI, kubectl, AWS CLI v2, Ansible.
FROM jenkins/jenkins:lts-jdk21

USER root

# Docker CLI + buildx plugin (talks to the host's Docker Desktop through the mounted socket)
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

RUN apt-get update \
 && apt-get install -y --no-install-recommends maven ansible-core curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# kubectl (latest stable)
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl

# AWS CLI v2
RUN curl -fsSLo /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
 && unzip -q /tmp/awscli.zip -d /tmp \
 && /tmp/aws/install \
 && rm -rf /tmp/aws /tmp/awscli.zip

# Plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration as Code: admin user, global env vars and the pipeline job
COPY casc.yaml /usr/share/jenkins/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc.yaml \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
