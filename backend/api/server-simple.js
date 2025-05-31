const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 8080;

// 中间件
app.use(cors());
app.use(express.json());

// 健康检查
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    timestamp: new Date().toISOString(),
    message: 'Popmart Stock Checker is running'
  });
});

// 首页
app.get('/', (req, res) => {
  res.json({
    message: 'Popmart Stock Checker API - Cloud Run Deploy',
    endpoints: {
      health: '/health',
      test: '/api/test',
      puppeteerTest: '/api/puppeteer-test',
      checkStock: '/api/check-stock?productId=1708',
      checkStockByUrl: '/api/check-stock?url=https://www.popmart.com/de/products/1708/...'
    },
    timestamp: new Date().toISOString()
  });
});

// 简单的测试API
app.get('/api/test', (req, res) => {
  res.json({
    message: 'Test API is working',
    timestamp: new Date().toISOString(),
    environment: process.env.NODE_ENV || 'development'
  });
});

// Puppeteer 测试API
app.get('/api/puppeteer-test', async (req, res) => {
  try {
    const puppeteer = require('puppeteer');
    
    const browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu'
      ]
    });

    const page = await browser.newPage();
    await page.goto('https://www.google.com');
    const title = await page.title();
    await browser.close();

    res.json({
      message: 'Puppeteer test successful',
      pageTitle: title,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({
      error: 'Puppeteer test failed',
      message: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// 主要的库存检查API
app.get('/api/check-stock', async (req, res) => {
  const { productId, url } = req.query;

  if (!productId && !url) {
    return res.status(400).json({ 
      error: 'Missing required parameter',
      message: '需要提供 productId 或 url 参数',
      examples: {
        byProductId: '/api/check-stock?productId=1708',
        byUrl: '/api/check-stock?url=https://www.popmart.com/de/products/1708/...'
      }
    });
  }

  const targetUrl = url || `https://www.popmart.com/de/products/${productId}/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll`;

  console.log(`正在检查商品库存: ${targetUrl}`);

  let browser;
  try {
    const puppeteer = require('puppeteer');
    
    // 启动浏览器
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--disable-gpu',
        '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows',
        '--disable-renderer-backgrounding'
      ],
      timeout: 60000
    });

    const page = await browser.newPage();
    
    // 设置更长的超时和更多选项
    page.setDefaultNavigationTimeout(60000);
    page.setDefaultTimeout(60000);
    
    // 设置用户代理
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    
    // 设置视口
    await page.setViewport({ width: 1920, height: 1080 });

    console.log('导航到页面...');
    
    // 导航到页面
    const response = await page.goto(targetUrl, { 
      waitUntil: 'domcontentloaded',
      timeout: 60000 
    });

    if (!response || !response.ok()) {
      throw new Error(`页面请求失败: ${response ? response.status() : '无响应'}`);
    }

    console.log('等待页面加载完成...');
    
    // 等待页面完全加载并增加更多等待时间
    try {
      await page.waitForFunction(() => {
        return document.readyState === 'complete' && 
               !document.querySelector('[class*="loading"]') &&
               !document.querySelector('[class*="spinner"]');
      }, { timeout: 30000 });
    } catch (e) {
      console.log('页面完成状态等待超时，继续执行...');
    }
    
    await page.waitForTimeout(8000); // 增加到8秒等待动态内容加载
    
    // 尝试等待一些常见的产品页面元素
    try {
      await page.waitForSelector('h1, .product-title, [data-testid*="title"], [data-testid*="name"], button', { timeout: 10000 });
    } catch (e) {
      console.log('未找到产品页面元素，继续执行...');
    }

    // 从URL中提取产品ID
    const urlMatch = targetUrl.match(/\/products\/(\d+)\//);
    const actualProductId = urlMatch ? urlMatch[1] : productId;

    console.log('提取页面信息...');

    // 注入增强的库存检测逻辑
    const pageInfo = await page.evaluate(() => {
      const result = {
        productName: '',
        price: '',
        inStock: null,
        stockReason: '',
        currentUrl: window.location.href,
        debug: {}
      };

      // 检查是否被重定向到主页
      if (document.title.includes('POP MART Official | Shop') && !window.location.pathname.includes('/products/')) {
        result.isRedirected = true;
        result.stockReason = '页面被重定向到主页，产品可能不存在';
        result.inStock = false;
        return result;
      }

      // 更全面的产品名称选择器（针对德语网站优化）
      const nameSelectors = [
        'h1[data-testid="pdp-product-name"]',
        'h1[class*="ProductName"]',
        'h1[class*="product-name"]', 
        'h1[class*="title"]',
        '.product-title',
        '.product-name',
        'h1',
        'h2',
        '[data-testid*="title"]',
        '[data-testid*="name"]',
        '[class*="product"][class*="name"]',
        '[class*="ProductDetail"][class*="title"]',
        '.pdp-product-name',
        '[data-cy="product-name"]',
        'h1[class*="Name"]',
        '.product-info h1',
        '.product-detail h1',
        'h1[class*="Product"]'
      ];

      for (const selector of nameSelectors) {
        const elements = document.querySelectorAll(selector);
        for (const element of elements) {
          if (element && element.textContent.trim() && element.textContent.trim().length > 3) {
            result.productName = element.textContent.trim();
            result.debug.nameSelector = selector;
            break;
          }
        }
        if (result.productName) break;
      }

      // 如果还没找到，尝试从页面标题提取
      if (!result.productName && document.title) {
        const titleParts = document.title.split('|')[0].split('-')[0].trim();
        if (titleParts && titleParts.length > 3 && !titleParts.toLowerCase().includes('popmart')) {
          result.productName = titleParts;
          result.debug.nameSelector = 'pageTitle';
        }
      }

      // 更全面的价格选择器（德语网站€符号）
      const priceSelectors = [
        '[data-testid="pdp-price"]',
        '[data-testid*="price"]',
        '.price',
        '[class*="price"]',
        '[class*="Price"]',
        '.cost',
        '.amount',
        '[class*="ProductPrice"]',
        '.pdp-price',
        '[data-cy="price"]',
        '.current-price',
        '.sale-price',
        '.product-price',
        '.price-current',
        '[class*="product"][class*="price"]'
      ];

      for (const selector of priceSelectors) {
        const elements = document.querySelectorAll(selector);
        for (const element of elements) {
          if (element && element.textContent.trim()) {
            const priceText = element.textContent.trim();
            // 匹配各种货币格式
            if (priceText.match(/[€$¥£]\s*\d+/) || priceText.match(/\d+[.,]\d+\s*[€$¥£]/) || priceText.match(/\d+[.,]\d+/)) {
              result.price = priceText;
              result.debug.priceSelector = selector;
              break;
            }
          }
        }
        if (result.price) break;
      }

      // 增强的按钮检查（获取所有按钮的详细信息）
      const buttonSelectors = [
        '[data-testid="pdp-add-to-cart"]',
        '[data-testid*="add-to-cart"]',
        'button[class*="add"]',
        'button[class*="cart"]',
        'button[class*="buy"]',
        'button[class*="Cart"]',
        'button[class*="AddToCart"]',
        '.add-to-cart',
        '.buy-now',
        '[data-testid*="add"]',
        'button[class*="warenkorb"]',
        'button[class*="hinzufügen"]',
        '[data-cy="add-to-cart"]',
        '.cart-button',
        '.add-button',
        'button[type="submit"]',
        'button[class*="Button"]'
      ];

      let foundMainButton = false;
      const allButtons = document.querySelectorAll('button');
      result.debug.totalButtons = allButtons.length;
      
      // 获取前10个按钮的详细信息
      const detailedButtons = Array.from(allButtons).slice(0, 10).map(btn => ({
        text: btn.textContent.trim(),
        disabled: btn.disabled || btn.classList.contains('disabled'),
        classes: btn.className,
        id: btn.id
      }));
      result.debug.detailedButtons = detailedButtons;
      
      // 获取所有按钮文本（前20个）
      result.debug.buttonTexts = Array.from(allButtons).slice(0, 20).map(btn => btn.textContent.trim()).filter(text => text.length > 0);

      // 寻找主要的购买按钮
      for (const selector of buttonSelectors) {
        const button = document.querySelector(selector);
        if (button) {
          foundMainButton = true;
          const buttonText = button.textContent.toLowerCase().trim();
          const isDisabled = button.disabled || 
                           button.classList.contains('disabled') || 
                           button.classList.contains('sold-out') ||
                           button.getAttribute('aria-disabled') === 'true' ||
                           button.hasAttribute('disabled');

          result.debug.mainButton = {
            text: button.textContent.trim(),
            disabled: isDisabled,
            classes: button.className,
            selector: selector
          };

          // 德语和英语缺货关键词
          const soldOutKeywords = [
            'ausverkauft', 'sold out', 'nicht verfügbar', 'unavailable',
            'coming soon', 'notify me', 'benachrichtigen', 'restocking',
            'out of stock', 'temporarily unavailable'
          ];

          // 德语和英语有货关键词  
          const availableKeywords = [
            'add', 'cart', 'buy', 'warenkorb', 'hinzufügen', 'kaufen',
            'in den warenkorb', 'add to cart', 'jetzt kaufen', 'purchase'
          ];

          const hasSoldOutKeyword = soldOutKeywords.some(keyword => buttonText.includes(keyword));
          const hasAvailableKeyword = availableKeywords.some(keyword => buttonText.includes(keyword));

          if (isDisabled || hasSoldOutKeyword) {
            result.inStock = false;
            result.stockReason = `主按钮显示缺货 - 文本: "${button.textContent.trim()}", 禁用: ${isDisabled}`;
          } else if (hasAvailableKeyword && !isDisabled) {
            result.inStock = true;
            result.stockReason = `找到可用的购买按钮: "${button.textContent.trim()}"`;
          }
          break;
        }
      }

      // 检查所有按钮的文本内容
      if (!foundMainButton || result.inStock === null) {
        let hasAvailableButton = false;
        let hasSoldOutButton = false;
        
        for (const btn of allButtons) {
          const btnText = btn.textContent.toLowerCase().trim();
          const isDisabled = btn.disabled || btn.classList.contains('disabled');
          
          if (btnText.includes('warenkorb') || btnText.includes('add to cart') || 
              btnText.includes('hinzufügen') || btnText.includes('kaufen') ||
              btnText.includes('buy') || btnText.includes('cart')) {
            if (isDisabled) {
              hasSoldOutButton = true;
              result.stockReason = `找到禁用的购买按钮: "${btn.textContent.trim()}"`;
            } else {
              hasAvailableButton = true;
              result.stockReason = `找到启用的购买按钮: "${btn.textContent.trim()}"`;
            }
          }
          
          if (btnText.includes('ausverkauft') || btnText.includes('sold out') || 
              btnText.includes('nicht verfügbar') || btnText.includes('notify')) {
            hasSoldOutButton = true;
            result.stockReason = `找到缺货按钮: "${btn.textContent.trim()}"`;
          }
        }
        
        if (hasSoldOutButton && !hasAvailableButton) {
          result.inStock = false;
        } else if (hasAvailableButton) {
          result.inStock = true;
        }
      }

      // 检查缺货提示文本
      const soldOutSelectors = [
        '[data-testid*="sold-out"]',
        '.sold-out',
        '.out-of-stock',
        '.unavailable',
        '[class*="SoldOut"]',
        '[class*="OutOfStock"]',
        '[class*="ausverkauft"]'
      ];

      for (const selector of soldOutSelectors) {
        const element = document.querySelector(selector);
        if (element && element.textContent.trim()) {
          result.inStock = false;
          result.stockReason = `找到缺货提示元素: "${element.textContent.trim()}"`;
          result.debug.hasSoldOutElement = true;
          break;
        }
      }

      // 检查页面整体文本中的库存关键词
      const pageText = document.body.textContent.toLowerCase();
      const soldOutTextKeywords = [
        'ausverkauft', 'sold out', 'nicht verfügbar', 'out of stock',
        'temporarily unavailable', 'currently unavailable', 'coming soon',
        'restocking soon', 'notify when available', 'benachrichtigen wenn verfügbar'
      ];

      const availableTextKeywords = [
        'in stock', 'available', 'verfügbar', 'auf lager', 'lieferbar',
        'sofort lieferbar', 'immediately available', 'jetzt verfügbar'
      ];

      // 只有在还没有确定库存状态时才使用页面文本判断
      if (result.inStock === null) {
        const soldOutMatches = soldOutTextKeywords.filter(keyword => pageText.includes(keyword));
        const availableMatches = availableTextKeywords.filter(keyword => pageText.includes(keyword));
        
        result.debug.textMatches = {
          soldOut: soldOutMatches,
          available: availableMatches
        };

        if (soldOutMatches.length > 0) {
          result.inStock = false;
          result.stockReason = `页面包含缺货关键词: ${soldOutMatches.join(', ')}`;
        } else if (availableMatches.length > 0) {
          result.inStock = true;
          result.stockReason = `页面包含有货关键词: ${availableMatches.join(', ')}`;
        } else if (foundMainButton && !result.debug.mainButton?.disabled) {
          // 如果找到了主按钮且未禁用，假设有货
          result.inStock = true;
          result.stockReason = '找到可用的主按钮，推测有库存';
        } else {
          // 更智能的默认判断：检查是否真的是产品页面
          const hasProductInfo = result.productName && result.price;
          if (hasProductInfo) {
            result.inStock = true;
            result.stockReason = '产品页面完整，未发现明确缺货标识，推测有库存';
          } else {
            result.inStock = false;
            result.stockReason = '无法获取完整产品信息，可能页面有问题';
          }
        }
      }

      // 额外的调试信息
      result.debug.foundSelectors = {
        productName: !!result.productName,
        price: !!result.price,
        buttons: allButtons.length,
        hasProductPage: window.location.pathname.includes('/products/'),
        pageTextLength: document.body.textContent.length,
        hasImages: document.querySelectorAll('img').length,
        pageTitle: document.title
      };

      return result;
    });

    await browser.close();

    // 构建响应
    const response_data = {
      success: true,
      productId: actualProductId,
      productName: pageInfo.productName || '未知产品',
      price: pageInfo.price || '价格未知',
      inStock: pageInfo.inStock,
      stockStatus: pageInfo.inStock === true ? 'available' : pageInfo.inStock === false ? 'sold_out' : 'unknown',
      stockReason: pageInfo.stockReason,
      url: targetUrl,
      currentUrl: pageInfo.currentUrl,
      timestamp: new Date().toISOString(),
      debug: pageInfo.debug
    };

    console.log('库存检查完成:', response_data);
    res.json(response_data);

  } catch (error) {
    if (browser) {
      await browser.close();
    }

    console.error('库存检查错误:', error);
    res.status(500).json({
      success: false,
      error: 'Stock check failed',
      message: error.message,
      productId: actualProductId,
      url: targetUrl,
      timestamp: new Date().toISOString()
    });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`🌐 Health check: http://localhost:${PORT}/health`);
  console.log(`📝 API docs: http://localhost:${PORT}/`);
}); 