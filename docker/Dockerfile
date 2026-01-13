FROM redhat/ubi8-minimal:latest

ENV USER=tibco \
    EMS_VERSION=10.4 \
    TIBCO_HOME=/opt/tibco

# Install required packages
RUN microdnf update -y && \
    microdnf install -y \
    tar \
    gzip \
    findutils \
    && microdnf clean all

# Create tibco user and necessary directories
RUN groupadd -g 2001 $USER && \
    useradd -r -u 2001 -g $USER $USER && \
    mkdir -p /scripts/destination && \
    mkdir -p ${TIBCO_HOME}/ems/${EMS_VERSION}

# Copy EMS client binaries (bin and lib directories)
# Note: These should be copied from your local EMS installation
# COPY ems-client/bin/ ${TIBCO_HOME}/ems/${EMS_VERSION}/bin/
# COPY ems-client/lib/ ${TIBCO_HOME}/ems/${EMS_VERSION}/lib/

# For now, we'll copy from the scripts directory which includes the binaries
COPY scripts/bin/ ${TIBCO_HOME}/ems/${EMS_VERSION}/bin/
COPY scripts/lib/ ${TIBCO_HOME}/ems/${EMS_VERSION}/lib/

# Copy the admin script
COPY scripts/ems-admin.sh /scripts/ems-admin.sh

# Set permissions
RUN chmod +x -R /scripts && \
    chmod +x ${TIBCO_HOME}/ems/${EMS_VERSION}/bin/* && \
    chown -R $USER:$USER /scripts && \
    chown -R $USER:$USER ${TIBCO_HOME}

# Switch to tibco user
USER $USER

# Set working directory
WORKDIR /scripts

# Default command
CMD ["sh", "/scripts/ems-admin.sh"]
