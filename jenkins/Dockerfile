# Jenkins controller with every tool the pipeline needs:
# JDK 21 (from base image), Maven, Docker CLI, kubectl, AWS CLI v2, Ansible.
FROM jenkins/jenkins:lts-jdk21

USER root

# Docker CLI + buildx plugin (talks to the host's Docker Desktop through the mounted socket)
COPY --from=docker:cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Use HTTPS mirrors (plain-HTTP downloads were being corrupted/timed out by the network) and retry.
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
 && apt-get -o Acquire::Retries=5 update \
 && apt-get -o Acquire::Retries=5 install -y --no-install-recommends ansible-core unzip \
 && rm -rf /var/lib/apt/lists/*

# Maven from Apache (Debian's maven package would pull in a second JRE; the base image already has JDK 21)
ARG MAVEN_VERSION=3.9.16
# Retry downloads: the build network drops TLS connections intermittently.
ARG CURL="curl -fsSL --retry 8 --retry-all-errors --retry-delay 3"
RUN $CURL -o /tmp/maven.tar.gz "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
 && tar -xzf /tmp/maven.tar.gz -C /opt && rm /tmp/maven.tar.gz \
 && ln -s /opt/apache-maven-${MAVEN_VERSION}/bin/mvn /usr/local/bin/mvn

# kubectl (latest stable), checksum verified
RUN KVER="$($CURL https://dl.k8s.io/release/stable.txt)" \
 && $CURL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl" \
 && echo "$($CURL https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl.sha256)  /usr/local/bin/kubectl" | sha256sum -c - \
 && chmod +x /usr/local/bin/kubectl

# AWS CLI v2
RUN $CURL -o /tmp/awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
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
