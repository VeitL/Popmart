import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';

export default async function handler(req, res) {
  // 设置CORS头
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { productId = '1707', url } = req.query;
  
  // 默认URL或从query参数获取
  const targetUrl = url || `https://www.popmart.com/de/products/${productId}/THE-MONSTERS-Let's-Checkmate-Series-Vinyl-Plush-Doll`;

  let browser = null;
  
  try {
    console.log(`开始检查产品: ${targetUrl}`);
    
    // 禁用WebGL以避免GPU相关错误
    chromium.setGraphicsMode = false;
    
    // 在Vercel上启动Puppeteer
    browser = await puppeteer.launch({
      args: chromium.args,
      defaultViewport: chromium.defaultViewport,
      executablePath: await chromium.executablePath(),
      headless: chromium.headless,
      ignoreHTTPSErrors: true,
    });

    const page = await browser.newPage();
    
    // 设置德国地区
    await page.setExtraHTTPHeaders({
      'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36'
    });

    // 设置cookies
    await page.setCookie(
      { name: 'locale', value: 'de', domain: '.popmart.com' },
      { name: 'region', value: 'DE', domain: '.popmart.com' },
      { name: 'currency', value: 'EUR', domain: '.popmart.com' }
    );

    console.log('正在访问页面...');
    await page.goto(targetUrl, { 
      waitUntil: 'networkidle2',
      timeout: 30000 
    });

    // 等待页面加载完成
    await page.waitForTimeout(3000);

    console.log('开始解析页面内容...');

    // 检查页面内容
    const pageInfo = await page.evaluate(() => {
      const title = document.title;
      const isMainPage = title.includes('POP MART Official | Shop');
      
      // 检查是否被重定向到主页
      if (isMainPage) {
        return {
          isRedirected: true,
          title,
          url: window.location.href
        };
      }

      // 查找产品信息
      const productName = document.querySelector('h1.product-title, .product-name, h1')?.innerText?.trim() || '';
      
      // 检查库存状态 - 多种方式
      const stockIndicators = {
        // 按钮状态检查
        addToCartButton: document.querySelector('button[class*="add-to-cart"], button[class*="warenkorb"], .btn-add-cart'),
        disabledButton: document.querySelector('button.disabled, button[disabled]'),
        soldOutButton: document.querySelector('button:contains("Ausverkauft"), button:contains("Sold Out")'),
        
        // 文本指示器
        soldOutText: document.querySelector('.sold-out, .ausverkauft, [class*="sold-out"], [class*="ausverkauft"]'),
        stockStatus: document.querySelector('.stock-status, .inventory-status, .product-status'),
        
        // 价格检查
        price: document.querySelector('.price, .product-price, [class*="price"]')?.innerText?.trim() || '',
        
        // 页面特征
        pageContent: document.body.innerText.toLowerCase()
      };

      // 判断库存状态
      let inStock = true;
      let stockReason = '';

      // 检查是否有"Ausverkauft"文本
      if (stockIndicators.pageContent.includes('ausverkauft')) {
        inStock = false;
        stockReason = '页面包含"Ausverkauft"文本';
      }

      // 检查按钮状态
      if (stockIndicators.disabledButton && 
          (stockIndicators.disabledButton.innerText.toLowerCase().includes('ausverkauft') ||
           stockIndicators.disabledButton.innerText.toLowerCase().includes('sold out'))) {
        inStock = false;
        stockReason = '按钮显示已售罄';
      }

      // 检查是否有可用的加入购物车按钮
      if (stockIndicators.addToCartButton && 
          !stockIndicators.addToCartButton.disabled &&
          (stockIndicators.addToCartButton.innerText.toLowerCase().includes('warenkorb') ||
           stockIndicators.addToCartButton.innerText.toLowerCase().includes('cart'))) {
        inStock = true;
        stockReason = '找到可用的加入购物车按钮';
      }

      return {
        isRedirected: false,
        productName,
        inStock,
        stockReason,
        price: stockIndicators.price,
        title,
        url: window.location.href,
        debug: {
          hasAddToCartButton: !!stockIndicators.addToCartButton,
          hasDisabledButton: !!stockIndicators.disabledButton,
          hasSoldOutText: !!stockIndicators.soldOutText,
          buttonText: stockIndicators.addToCartButton?.innerText || '',
          pageContentSample: stockIndicators.pageContent.substring(0, 200)
        }
      };
    });

    console.log('页面解析结果:', pageInfo);

    if (pageInfo.isRedirected) {
      return res.status(200).json({
        success: false,
        error: '页面被重定向到主页，可能是产品不存在或链接错误',
        data: {
          title: pageInfo.title,
          currentUrl: pageInfo.url,
          originalUrl: targetUrl
        }
      });
    }

    return res.status(200).json({
      success: true,
      data: {
        productId,
        productName: pageInfo.productName,
        inStock: pageInfo.inStock,
        stockReason: pageInfo.stockReason,
        price: pageInfo.price,
        url: pageInfo.url,
        timestamp: new Date().toISOString(),
        debug: pageInfo.debug
      }
    });

  } catch (error) {
    console.error('检查库存时出错:', error);
    
    return res.status(500).json({
      success: false,
      error: error.message,
      data: {
        productId,
        url: targetUrl,
        timestamp: new Date().toISOString()
      }
    });
  } finally {
    if (browser) {
      try {
        // 确保所有页面都被关闭
        for (const page of await browser.pages()) {
          await page.close();
        }
        await browser.close();
      } catch (closeError) {
        console.error('关闭浏览器时出错:', closeError);
      }
    }
  }
} 