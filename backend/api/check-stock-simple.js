import * as cheerio from 'cheerio';

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

  try {
    console.log(`开始检查产品: ${targetUrl}`);
    
    // 使用fetch获取页面内容
    const response = await fetch(targetUrl, {
      headers: {
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Cookie': 'locale=de; region=DE; currency=EUR'
      },
      timeout: 30000
    });

    if (!response.ok) {
      throw new Error(`HTTP错误: ${response.status} ${response.statusText}`);
    }

    const html = await response.text();
    console.log('页面内容获取成功，开始解析...');

    // 使用cheerio解析HTML
    const result = parseHTML(html, targetUrl);

    console.log('解析结果:', result);

    return res.status(200).json({
      success: true,
      data: {
        productId: result.actualProductId || productId,
        productName: result.productName,
        inStock: result.inStock,
        stockReason: result.stockReason,
        price: result.price,
        url: targetUrl,
        timestamp: new Date().toISOString(),
        debug: result.debug
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
  }
}

function parseHTML(html, url) {
  const $ = cheerio.load(html);
  
  // 从URL中提取正确的产品ID
  const urlMatch = url.match(/\/products\/(\d+)\//);
  const actualProductId = urlMatch ? urlMatch[1] : '';
  
  // 检查是否被重定向到主页
  const title = $('title').text();
  const isMainPage = title.includes('POP MART Official | Shop');
  
  if (isMainPage) {
    return {
      isRedirected: true,
      productName: '',
      inStock: false,
      stockReason: '页面被重定向到主页，可能是产品不存在或链接错误',
      price: '',
      actualProductId,
      debug: {
        title,
        hasAddToCartButton: false,
        hasDisabledButton: false,
        hasSoldOutText: false,
        buttonText: '',
        pageContentSample: $('body').text().substring(0, 200)
      }
    };
  }

  // 尝试从JavaScript内容中提取产品信息
  let productName = '';
  let price = '';
  let inStock = null; // null表示未知状态
  let stockReason = '分析JavaScript内容中...';
  let foundData = false;
  
  // 查找script标签中的产品数据
  $('script').each((index, element) => {
    const scriptContent = $(element).html() || '';
    
    // 尝试从window.__NUXT__或类似的全局变量中提取数据
    if (scriptContent.includes('window.__NUXT__') || scriptContent.includes('window.__INITIAL_STATE__')) {
      try {
        // 查找产品相关的JSON数据
        const matches = scriptContent.match(/window\.__NUXT__\s*=\s*(.+);/);
        if (matches) {
          const nuxtData = JSON.parse(matches[1]);
          console.log('找到NUXT数据:', JSON.stringify(nuxtData).substring(0, 500));
          
          // 递归搜索产品信息
          const findProductInfo = (obj, path = '') => {
            if (obj && typeof obj === 'object') {
              for (const [key, value] of Object.entries(obj)) {
                if (key.toLowerCase().includes('product') || key.toLowerCase().includes('item')) {
                  if (value && typeof value === 'object') {
                    if (value.name || value.title) {
                      productName = value.name || value.title || productName;
                      foundData = true;
                    }
                    if (value.price !== undefined) {
                      price = value.price.toString();
                      foundData = true;
                    }
                    if (value.inStock !== undefined || value.available !== undefined) {
                      inStock = value.inStock || value.available;
                      stockReason = `从${path}获取库存状态: ${inStock ? '有库存' : '缺货'}`;
                      foundData = true;
                    }
                    if (value.stock !== undefined) {
                      inStock = value.stock > 0;
                      stockReason = `库存数量: ${value.stock}`;
                      foundData = true;
                    }
                  }
                }
                
                // 递归搜索
                if (typeof value === 'object' && value !== null) {
                  findProductInfo(value, `${path}.${key}`);
                }
              }
            }
          };
          
          findProductInfo(nuxtData, 'nuxt');
        }
      } catch (e) {
        console.log('解析NUXT数据失败:', e.message);
      }
    }
    
    // 查找其他可能的数据结构
    if (scriptContent.includes('"product"') || scriptContent.includes('"item"')) {
      try {
        // 使用正则表达式查找JSON对象
        const jsonMatches = scriptContent.match(/\{[^{}]*"[^"]*"[^{}]*\}/g);
        if (jsonMatches) {
          for (const jsonStr of jsonMatches) {
            try {
              const data = JSON.parse(jsonStr);
              if (data.name || data.title || data.productName) {
                productName = data.name || data.title || data.productName || productName;
                foundData = true;
              }
              if (data.price !== undefined) {
                price = data.price.toString();
                foundData = true;
              }
              if (data.inStock !== undefined || data.available !== undefined) {
                inStock = data.inStock || data.available;
                stockReason = `从JSON数据获取: ${inStock ? '有库存' : '缺货'}`;
                foundData = true;
              }
            } catch (e) {
              // 忽略无效JSON
            }
          }
        }
      } catch (e) {
        console.log('解析JSON数据失败:', e.message);
      }
    }
  });

  // 如果没有从JavaScript获取到信息，尝试HTML解析
  if (!foundData) {
    // 查找产品名称
    const nameSelectors = [
      'h1[class*="title"]',
      '.product-title',
      '.product-name',
      'h1',
      '[data-testid*="title"]',
      '[class*="product"][class*="name"]'
    ];
    
    for (const selector of nameSelectors) {
      const element = $(selector).first();
      if (element.length && element.text().trim()) {
        productName = element.text().trim();
        break;
      }
    }
    
    // 查找价格
    const priceSelectors = [
      '.price',
      '[class*="price"]',
      '[data-testid*="price"]',
      '.cost',
      '.amount'
    ];
    
    for (const selector of priceSelectors) {
      const element = $(selector).first();
      if (element.length && element.text().trim()) {
        price = element.text().trim();
        break;
      }
    }
    
    // 检查库存状态
    const pageText = $('body').text().toLowerCase();
    
    // 检查缺货关键词
    const soldOutKeywords = [
      'ausverkauft', 'sold out', 'nicht verfügbar', 'out of stock',
      'temporarily unavailable', 'currently unavailable', 'coming soon'
    ];
    
    const hasSoldOutText = soldOutKeywords.some(keyword => pageText.includes(keyword));
    
    // 检查按钮状态
    const buttonSelectors = [
      'button[class*="add"]',
      'button[class*="cart"]',
      'button[class*="buy"]',
      '.add-to-cart',
      '.buy-now',
      '[data-testid*="add"]'
    ];
    
    let buttonFound = false;
    let buttonText = '';
    
    for (const selector of buttonSelectors) {
      const button = $(selector).first();
      if (button.length) {
        buttonFound = true;
        buttonText = button.text().trim().toLowerCase();
        
        if (buttonText.includes('ausverkauft') || buttonText.includes('sold out') || 
            buttonText.includes('nicht verfügbar') || button.is(':disabled') || 
            button.hasClass('disabled')) {
          inStock = false;
          stockReason = '按钮显示缺货或被禁用';
        } else if (buttonText.includes('add') || buttonText.includes('cart') || 
                   buttonText.includes('buy') || buttonText.includes('warenkorb')) {
          inStock = true;
          stockReason = '找到可用的购买按钮';
        }
        break;
      }
    }
    
    // 如果找到了缺货文本但没有按钮信息，则判断为缺货
    if (hasSoldOutText && inStock === null) {
      inStock = false;
      stockReason = '页面包含缺货关键词';
    }
    
    // 如果什么都没找到，诚实地报告
    if (inStock === null) {
      inStock = false;
      stockReason = `无法确定库存状态 - 网站使用JavaScript渲染，需要浏览器解析。产品ID: ${actualProductId}`;
    }
  }

  return {
    isRedirected: false,
    productName: productName || `Popmart商品 ${actualProductId}`,
    inStock: inStock !== null ? inStock : false,
    stockReason: stockReason || '无法获取库存信息',
    price: price || '价格需要在网站上查看',
    actualProductId,
    debug: {
      title,
      extractedProductId: actualProductId,
      foundJSData: foundData,
      hasAddToCartButton: $('button[class*="add"], button[class*="cart"]').length > 0,
      hasDisabledButton: $('button.disabled, button[disabled]').length > 0,
      hasSoldOutText: $('body').text().toLowerCase().includes('ausverkauft'),
      buttonText: $('button').first().text().trim() || '未找到按钮',
      pageContentSample: $('body').text().substring(0, 300)
    }
  };
} 