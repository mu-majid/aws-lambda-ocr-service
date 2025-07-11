const AWS = require('aws-sdk');
const textract = new AWS.Textract({ region: 'eu-central-1' });
const rekognition = new AWS.Rekognition({ region: 'eu-central-1' });

exports.handler = async (event) => {
  console.log('Target lambda event:', JSON.stringify(event, null, 2));
  
  try {
    const { image } = event;
    
    if (!image) {
      console.log('No image provided to target lambda');
      return {
        success: false,
        error: 'No image provided'
      };
    }
    const imageBuffer = Buffer.from(image, 'base64');
    // Run both OCR services in parallel
    const ocrResults = await Promise.allSettled([
      performTextractOCR(imageBuffer),
      performRekognitionOCR(imageBuffer)
    ]);

    const processedResults = processOCRResults(ocrResults); // find best confidence
    const bestResult = findBestResult(processedResults);

    const response = {
      success: true,
      data: {
        bestResult: bestResult,
        allResults: processedResults,
        processingInfo: {
          imageSize: imageBuffer.length,
          imageType: getImageType(image),
          timestamp: new Date().toISOString(),
          servicesUsed: ['textract', 'rekognition']
        }
      }
    };
    console.log('Response :', JSON.stringify(response, null, 2));

    return response;
  } 
  catch (error) {
    console.error('Error in target lambda:', error);
    return {
      success: false,
      error: error.message,
      type: error.constructor.name
    };
  }
};

async function performTextractOCR(imageBuffer) {
  try {    
    const params = {
      Document: {
        Bytes: imageBuffer
      }
    };

    const result = await textract.detectDocumentText(params).promise();
    let fullText = '';
    let totalConfidence = 0;
    let wordCount = 0;

    result.Blocks.forEach(block => {
      if (block.BlockType === 'WORD') {
        fullText += block.Text + ' ';
        totalConfidence += block.Confidence;
        wordCount++;
      }
    });

    const averageConfidence = wordCount > 0 ? totalConfidence / wordCount : 0;

    return {
      success: true,
      source: 'textract',
      text: fullText.trim(),
      confidence: averageConfidence / 100, // Convert to 0-1 scale
      wordCount: wordCount,
      rawData: result
    };

  } catch (error) {
    console.error('Textract OCR failed:', error);
    return {
      success: false,
      source: 'textract',
      error: error.message
    };
  }
}
async function performRekognitionOCR(imageBuffer) {
  try {    
    const params = {
      Image: {
        Bytes: imageBuffer
      }
    };

    const result = await rekognition.detectText(params).promise();
    let fullText = '';
    let totalConfidence = 0;
    let wordCount = 0;

    result.TextDetections.forEach(detection => {
      if (detection.Type === 'WORD') {
        fullText += detection.DetectedText + ' ';
        totalConfidence += detection.Confidence;
        wordCount++;
      }
    });

    const averageConfidence = wordCount > 0 ? totalConfidence / wordCount : 0;

    return {
      success: true,
      source: 'rekognition',
      text: fullText.trim(),
      confidence: averageConfidence / 100, // Convert to 0-1 scale
      wordCount: wordCount,
      rawData: result
    };

  } catch (error) {
    console.error('Rekognition OCR failed:', error);
    return {
      success: false,
      source: 'rekognition',
      error: error.message
    };
  }
}

function processOCRResults(ocrResults) {
  const processedResults = [];

  ocrResults.forEach((result, index) => {
    const serviceName = index === 0 ? 'textract' : 'rekognition';
    
    if (result.status === 'fulfilled' && result.value.success) {
      processedResults.push(result.value);
    } else {
      console.warn(`${serviceName} failed:`, result.reason || result.value.error);
      processedResults.push({
        success: false,
        source: serviceName,
        error: result.reason?.message || result.value?.error || 'Unknown error'
      });
    }
  });

  return processedResults;
}

function findBestResult(results) {
  const successfulResults = results.filter(result => result.success);
  
  if (successfulResults.length === 0) {
    return {
      source: 'none',
      text: '',
      confidence: 0,
      error: 'All OCR services failed'
    };
  }

  const bestResult = successfulResults.reduce((best, current) => {
    return current.confidence > best.confidence ? current : best;
  });

  return {
    source: bestResult.source,
    text: bestResult.text,
    confidence: bestResult.confidence,
    wordCount: bestResult.wordCount
  };
}

function getImageType(base64String) {
  try {
    if (!base64String) return 'unknown';
    
    if (base64String.startsWith('/9j/')) return 'jpeg';
    if (base64String.startsWith('iVBORw0KGgo')) return 'png';
    if (base64String.startsWith('R0lGOD')) return 'gif';
    return 'unknown';
  } catch (error) {
    console.error('Error determining image type:', error);
    return 'unknown';
  }
}