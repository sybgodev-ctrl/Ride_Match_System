// GoApp Kafka Event Bus — real Apache Kafka via kafkajs
//
// API:
//   publish(topic, payload)               → void  (fire-and-forget)
//   subscribe(topic, groupId, handler)    → Promise<void>
//   getRecentEvents(n)                    → Array (always empty in real mode)

'use strict';

const config = require('../config');
const { logger } = require('../utils/logger');

class RealKafkaBus {
  constructor() {
    this._producer  = null;
    this._consumers = new Map(); // `${topic}:${groupId}` → consumer
    this._ready     = false;
  }

  async connect() {
    const { Kafka, logLevel } = require('kafkajs');
    const kafka = new Kafka({
      clientId:  config.kafka.clientId  || 'goapp-server',
      brokers:   config.kafka.brokers   || ['localhost:9092'],
      logLevel:  logLevel.WARN,
      retry: { initialRetryTime: 200, retries: 8 },
    });

    this._kafka    = kafka;
    this._producer = kafka.producer({ allowAutoTopicCreation: true });
    await this._producer.connect();
    this._ready = true;
    logger.info('KAFKA', `Producer connected to ${(config.kafka.brokers || ['localhost:9092']).join(',')}`);
  }

  publish(topic, payload) {
    if (!this._ready) {
      logger.warn('KAFKA', `Producer not ready — dropping event: ${topic}`);
      return;
    }
    this._producer.send({
      topic,
      messages: [{ value: JSON.stringify({ ...payload, _ts: Date.now() }) }],
    }).catch(err => logger.error('KAFKA', `Publish failed [${topic}]: ${err.message}`));
  }

  async subscribe(topic, groupId, handler) {
    if (!this._kafka) throw new Error('Kafka not connected. Call connect() first.');

    const consumer = this._kafka.consumer({
      groupId,
      sessionTimeout:   30000,
      heartbeatInterval: 3000,
    });

    await consumer.connect();
    await consumer.subscribe({ topic, fromBeginning: false });
    await consumer.run({
      eachMessage: async ({ message }) => {
        try {
          if (!message || message.value == null) return;
          const payload = JSON.parse(message.value.toString());
          await handler(payload);
        } catch (err) {
          logger.error('KAFKA', `Consumer error [${topic}/${groupId}]: ${err.message}`);
        }
      },
    });

    this._consumers.set(`${topic}:${groupId}`, consumer);
    logger.info('KAFKA', `Subscribed to [${topic}] as group [${groupId}]`);
  }

  // Graceful shutdown
  async disconnect() {
    for (const c of this._consumers.values()) {
      await c.disconnect().catch(() => {});
    }
    if (this._producer) await this._producer.disconnect().catch(() => {});
    this._ready = false;
    logger.info('KAFKA', 'Disconnected');
  }

  getRecentEvents() { return []; } // not buffered in real mode

  getStats() {
    return {
      backend:   'real',
      ready:     this._ready,
      consumers: this._consumers.size,
      brokers:   config.kafka?.brokers || ['localhost:9092'],
    };
  }
}

// ─── Factory & Export ─────────────────────────────────────────────────────────

const client = new RealKafkaBus();
client.connect().catch(err => {
  logger.error('KAFKA', `Initial connection failed: ${err.message}`);
  process.nextTick(() => process.exit(1));
});

module.exports = client;
