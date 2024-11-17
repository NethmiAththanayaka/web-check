# Specify the Node.js version to use
ARG NODE_VERSION=21

# Specify the Debian version to use, the default is "bullseye"
ARG DEBIAN_VERSION=bullseye

# Use Node.js Docker image as the base image, with specific Node and Debian versions
FROM node:${NODE_VERSION}-${DEBIAN_VERSION} AS build

# Set the container's default shell to Bash and enable some options
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Install Chromium browser, its dependencies, and other build tools
RUN apt-get update -qq --fix-missing && \
    apt-get -qqy install --allow-unauthenticated gnupg wget && \
    wget --quiet --output-document=- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /etc/apt/trusted.gpg.d/google-archive.gpg && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google.list && \
    apt-get update -qq && \
    apt-get -qqy --no-install-recommends install chromium traceroute python make g++ && \
    rm -rf /var/lib/apt/lists/*

# Verify the Chromium installation
RUN /usr/bin/chromium --no-sandbox --version > /etc/chromium-version

# Set the working directory to /app
WORKDIR /app

# Copy package.json and yarn.lock to the working directory
COPY package.json yarn.lock ./

# Install dependencies and clear yarn cache
RUN apt-get update && \
    yarn install --frozen-lockfile --network-timeout 100000 && \
    rm -rf /app/node_modules/.cache

# Copy all application files to the working directory
COPY . .

# Build the application
RUN yarn build --production

# Final stage for runtime
FROM node:${NODE_VERSION}-${DEBIAN_VERSION} AS final

# Set the working directory
WORKDIR /app

# Create an unprivileged user with a specific UID/GID within range 10000-20000
RUN adduser \
  --disabled-password \
  --gecos "" \
  --home "/nonexistent" \
  --shell "/sbin/nologin" \
  --no-create-home \
  --uid 10014 \
  "choreo"

# Use the above-created unprivileged user
USER 10014

# Copy necessary files from the build stage
COPY package.json yarn.lock ./
COPY --from=build /app ./

# Install runtime dependencies (if needed) as the root user, ensuring permissions
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends chromium traceroute && \
    chmod 755 /usr/bin/chromium && \
    rm -rf /var/lib/apt/lists/* /app/node_modules/.cache

# Switch back to the unprivileged user
USER 10014

# Expose the container port, default is 3000, but it can be modified through the environment variable PORT
EXPOSE ${PORT:-9090}

# Set the environment variable for Chromium's path
ENV CHROME_PATH='/usr/bin/chromium'

# Define the command executed when the container starts
CMD ["yarn", "start"]
