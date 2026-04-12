ARG MATLAB_BASE_IMAGE=mathworks/matlab:r2025b
FROM ${MATLAB_BASE_IMAGE}

USER root

ARG MATLAB_RELEASE=R2025b
ARG MATLAB_PRODUCTS="MATLAB MATLAB_Coder HDL_Coder Fixed-Point_Designer"

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget \
 && rm -rf /var/lib/apt/lists/*

RUN wget -q -O /tmp/mpm https://www.mathworks.com/mpm/glnxa64/mpm \
 && chmod +x /tmp/mpm \
 && /tmp/mpm install \
      --release="${MATLAB_RELEASE}" \
      --destination="/opt/matlab/${MATLAB_RELEASE}" \
      --products ${MATLAB_PRODUCTS} \
 && rm -f /tmp/mpm /tmp/mathworks_root.log

USER matlab
