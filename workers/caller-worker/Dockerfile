FROM node:20-alpine AS builder

WORKDIR /app

# Copy dependency files and install full deps to build
COPY package*.json ./
RUN npm ci --silent

# Copy source and build
COPY . .
RUN npm run build

FROM node:20-alpine AS runtime

WORKDIR /app

# Only install production dependencies in the runtime image
COPY package*.json ./
RUN npm ci --production --silent

# Copy built artifacts from builder
COPY --from=builder /app/dist ./dist

# Default environment variables
ENV III_URL=ws://localhost:49134
ENV NODE_ENV=production

# Run as non-root user for better security
RUN addgroup -S app && adduser -S app -G app
USER app

# Start the worker
CMD ["node", "dist/worker.js"]
