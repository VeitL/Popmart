const express = require('express');
const cors = require('cors');
const path = require('path');

// 动态导入 API 处理函数
const testHandler = require('./test.js');
const simpleStockHandler = require('./check-stock-simple.js');
const puppeteerStockHandler = require('./check-stock-puppeteer.js');

const app = express();
const PORT = process.env.PORT || 8080;

// 中间件
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// 创建模拟的 req, res 对象适配器
function createHandler(handler) {
  return async (req, res) => {
    try {
      // 创建兼容 Vercel 的 req 对象
      const vercelReq = {
        method: req.method,
        query: req.query,
        body: req.body,
        headers: req.headers
      };

      // 创建兼容 Vercel 的 res 对象
      const vercelRes = {
        status: (code) => {
          res.status(code);
          return vercelRes;
        },
        json: (data) => {
          res.json(data);
          return vercelRes;
        },
        end: () => {
          res.end();
          return vercelRes;
        },
        setHeader: (name, value) => {
          res.setHeader(name, value);
          return vercelRes;
        }
      };

      await handler.default(vercelReq, vercelRes);
    } catch (error) {
      console.error('Handler error:', error);
      res.status(500).json({ error: error.message });
    }
  };
}

// API 路由
app.get('/api/test', createHandler(testHandler));
app.get('/api/check-stock-simple', createHandler(simpleStockHandler));
app.get('/api/check-stock-puppeteer', createHandler(puppeteerStockHandler));

// 健康检查
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    puppeteer: 'ready'
  });
});

// 首页
app.get('/', (req, res) => {
  res.json({
    message: 'Popmart Stock Checker API - Render Deploy',
    endpoints: {
      test: '/api/test',
      simpleStock: '/api/check-stock-simple?productId=1708',
      puppeteerStock: '/api/check-stock-puppeteer?productId=1708',
      health: '/health'
    },
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`🌐 Health check: http://localhost:${PORT}/health`);
  console.log(`📝 API docs: http://localhost:${PORT}/`);
}); 