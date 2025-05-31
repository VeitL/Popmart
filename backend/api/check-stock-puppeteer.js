const puppeteer = require('puppeteer');

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { productId, url } = req.query;

  if (!productId && !url) {
    return res.status(400).json({ 
      error: 'Missing required parameter',
      message: '需要提供 productId 或 url 参数'
    });
  }

  const targetUrl = url || `https://www.popmart.com/de/products/${productId}/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll`;

  console.log(`正在检查商品库存: ${targetUrl}`);

  let browser;
  try {
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
        '--disable-gpu'
      ]
    });

    const page = await browser.newPage();
    
    // 设置用户代理
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    
    // 设置视口
    await page.setViewport({ width: 1920, height: 1080 });

    console.log('导航到页面...');
    
    // 导航到页面
    const response = await page.goto(targetUrl, { 
      waitUntil: 'networkidle2',
      timeout: 30000 
    });

    if (!response || !response.ok()) {
      throw new Error(`页面请求失败: ${response ? response.status() : '无响应'}`);
    }

    console.log('等待页面加载完成...');
    
    // 等待页面完全加载
    await page.waitForTimeout(3000);

    // 从URL中提取产品ID
    const urlMatch = targetUrl.match(/\/products\/(\d+)\//);
    const actualProductId = urlMatch ? urlMatch[1] : productId;

    console.log('提取页面信息...');

    // 执行页面脚本来提取信息
    const pageInfo = await page.evaluate(() => {
      const result = {
        productName: '',
        price: '',
        inStock: null,
        stockReason: '',
        pageTitle: document.title,
        isRedirected: false,
        debug: {}
      };

      // 检查是否被重定向到主页
      if (document.title.includes('POP MART Official | Shop') && !window.location.pathname.includes('/products/')) {
        result.isRedirected = true;
        result.stockReason = '页面被重定向到主页，产品可能不存在';
        result.inStock = false;
        return result;
      }

      // 尝试多种方式获取产品名称
      const nameSelectors = [
        'h1[class*="title"]',
        '.product-title',
        '.product-name',
        'h1',
        '[data-testid*="title"]',
        '[class*="product"][class*="name"]',
        '[class*="ProductDetail"][class*="title"]'
      ];

      for (const selector of nameSelectors) {
        const element = document.querySelector(selector);
        if (element && element.textContent.trim()) {
          result.productName = element.textContent.trim();
          break;
        }
      }

      // 尝试多种方式获取价格
      const priceSelectors = [
        '.price',
        '[class*="price"]',
        '[data-testid*="price"]',
        '.cost',
        '.amount',
        '[class*="Price"]'
      ];

      for (const selector of priceSelectors) {
        const element = document.querySelector(selector);
        if (element && element.textContent.trim()) {
          const priceText = element.textContent.trim();
          if (priceText.match(/[€$¥£]\s*\d+/) || priceText.match(/\d+[.,]\d+/)) {
            result.price = priceText;
            break;
          }
        }
      }

      // 检查库存状态 - 查找按钮
      const buttonSelectors = [
        'button[class*="add"]',
        'button[class*="cart"]',
        'button[class*="buy"]',
        '.add-to-cart',
        '.buy-now',
        '[data-testid*="add"]',
        'button[class*="AddToCart"]',
        'button[class*="warenkorb"]'
      ];

      let foundButton = false;
      for (const selector of buttonSelectors) {
        const button = document.querySelector(selector);
        if (button) {
          foundButton = true;
          const buttonText = button.textContent.toLowerCase();
          const isDisabled = button.disabled || button.classList.contains('disabled') || 
                           button.getAttribute('aria-disabled') === 'true';

          result.debug.buttonText = button.textContent.trim();
          result.debug.isButtonDisabled = isDisabled;

          if (isDisabled || buttonText.includes('ausverkauft') || 
              buttonText.includes('sold out') || buttonText.includes('nicht verfügbar') ||
              buttonText.includes('coming soon')) {
            result.inStock = false;
            result.stockReason = `按钮显示缺货: "${button.textContent.trim()}"`;
          } else if (buttonText.includes('add') || buttonText.includes('cart') || 
                     buttonText.includes('buy') || buttonText.includes('warenkorb') ||
                     buttonText.includes('hinzufügen')) {
            result.inStock = true;
            result.stockReason = `找到可用的购买按钮: "${button.textContent.trim()}"`;
          }
          break;
        }
      }

      // 检查页面文本中的库存关键词
      const pageText = document.body.textContent.toLowerCase();
      const soldOutKeywords = [
        'ausverkauft', 'sold out', 'nicht verfügbar', 'out of stock',
        'temporarily unavailable', 'currently unavailable', 'coming soon',
        'restocking soon', 'notify when available'
      ];

      const availableKeywords = [
        'in stock', 'available', 'verfügbar', 'auf lager', 'lieferbar'
      ];

      if (result.inStock === null) {
        const hasSoldOutText = soldOutKeywords.some(keyword => pageText.includes(keyword));
        const hasAvailableText = availableKeywords.some(keyword => pageText.includes(keyword));

        if (hasSoldOutText) {
          result.inStock = false;
          result.stockReason = '页面包含缺货关键词';
        } else if (hasAvailableText) {
          result.inStock = true;
          result.stockReason = '页面包含有货关键词';
        }
      }

      // 检查特定的缺货元素
      const soldOutElements = document.querySelectorAll(
        '.sold-out, .ausverkauft, [class*="sold-out"], [class*="ausverkauft"], ' +
        '.out-of-stock, [class*="unavailable"], [class*="SoldOut"]'
      );

      if (soldOutElements.length > 0 && result.inStock === null) {
        result.inStock = false;
        result.stockReason = '找到缺货样式元素';
      }

      // 如果仍然无法确定，根据是否找到有效按钮来判断
      if (result.inStock === null) {
        if (foundButton) {
          result.inStock = true;
          result.stockReason = '找到购买按钮，推测有货';
        } else {
          result.inStock = false;
          result.stockReason = '未找到购买按钮，推测缺货';
        }
      }

      // 添加调试信息
      result.debug.hasButtons = foundButton;
      result.debug.pageTextSample = pageText.substring(0, 300);
      result.debug.soldOutElements = soldOutElements.length;

      return result;
    });

    await browser.close();

    console.log('页面信息提取完成:', pageInfo);

    return res.status(200).json({
      success: true,
      data: {
        productId: actualProductId,
        productName: pageInfo.productName || `Popmart商品 ${actualProductId}`,
        inStock: pageInfo.inStock,
        stockReason: pageInfo.stockReason || '库存状态检查完成',
        price: pageInfo.price || '价格需要在网站上查看',
        url: targetUrl,
        timestamp: new Date().toISOString(),
        debug: {
          pageTitle: pageInfo.pageTitle,
          isRedirected: pageInfo.isRedirected,
          extractedProductId: actualProductId,
          ...pageInfo.debug
        }
      }
    });

  } catch (error) {
    console.error('Puppeteer错误:', error);
    
    if (browser) {
      await browser.close();
    }

    return res.status(500).json({
      success: false,
      error: error.message,
      data: {
        productId: productId,
        productName: `Popmart商品 ${productId}`,
        inStock: false,
        stockReason: `获取库存信息失败: ${error.message}`,
        price: '价格无法获取',
        url: targetUrl,
        timestamp: new Date().toISOString()
      }
    });
  }
} 