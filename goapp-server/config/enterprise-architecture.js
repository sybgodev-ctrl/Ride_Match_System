// GoApp Enterprise Architecture Settings
// Microservice-ready runtime defaults + AWS deployment hints

module.exports = {
  runtime: {
    nodeEnv: process.env.NODE_ENV || 'development',
    serviceName: process.env.SERVICE_NAME || 'goapp-api-gateway',
    region: process.env.AWS_REGION || 'ap-south-1',
  },

  performance: {
    enableWarmStart: true,
    bootstrapBatchSize: 250,
    httpKeepAliveMs: 65000,
    requestTimeoutMs: 15000,
  },

  microservices: {
    gateway: { service: 'api-gateway', port: 3000 },
    location: { service: 'location-service', port: 3011 },
    matching: { service: 'matching-service', port: 3012 },
    pricing: { service: 'pricing-service', port: 3013 },
    rides: { service: 'ride-service', port: 3014 },
    events: { service: 'event-service', port: 3015 },
  },

  aws: {
    compute: {
      preferred: 'ECS_FARGATE',
      alternatives: ['EKS', 'Lambda'],
    },
    networking: {
      lb: 'ALB',
      privateSubnets: true,
      waf: true,
    },
    observability: {
      logs: 'CloudWatch Logs',
      traces: 'AWS X-Ray / OpenTelemetry',
      metrics: 'CloudWatch Metrics',
    },
    dataPlane: {
      cache: 'ElastiCache Redis',
      eventStreaming: 'MSK/Kinesis',
      futureDatabases: ['Aurora PostgreSQL', 'DynamoDB'],
    },
  },
};
