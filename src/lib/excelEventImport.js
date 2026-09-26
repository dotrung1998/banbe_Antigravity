import JSZip from 'jszip';

// Canonical categories definition matching project standards
export const CANONICAL_CATEGORIES = [
  { key: 'supper', vi: 'Supper club', en: 'Supper club' },
  { key: 'fashion', vi: 'Thời trang', en: 'Fashion' },
  { key: 'gallery', vi: 'Phòng tranh', en: 'Gallery' },
  { key: 'music', vi: 'Nhạc', en: 'Music' },
  { key: 'popup', vi: 'Pop-up', en: 'Pop-up' },
];

export function normalizeCategory(catStr) {
  if (!catStr) return { key: 'supper', label: 'Supper club' };
  const raw = String(catStr).trim().toLowerCase();
  if (['supper', 'supper club', 'supper_club', 'ẩm thực', 'am thuc', 'food'].includes(raw)) {
    return { key: 'supper', label: 'Supper club' };
  }
  if (['fashion', 'thời trang', 'thoi trang'].includes(raw)) {
    return { key: 'fashion', label: 'Thời trang' };
  }
  if (['gallery', 'phòng tranh', 'phong tranh', 'triển lãm', 'trien lam', 'art'].includes(raw)) {
    return { key: 'gallery', label: 'Phòng tranh' };
  }
  if (['music', 'nhạc', 'nhac', 'âm nhạc', 'am nhac'].includes(raw)) {
    return { key: 'music', label: 'Nhạc' };
  }
  if (['popup', 'pop-up', 'pop up'].includes(raw)) {
    return { key: 'popup', label: 'Pop-up' };
  }
  return { key: raw.replace(/\s+/g, '-'), label: catStr.trim() };
}

/** Sanitize text against formula injection and unwanted formatting */
export function sanitizePlainText(val) {
  if (val == null) return '';
  let str = String(val).trim();
  // Strip formula prefixes
  if (/^[=+@-]/.test(str)) {
    str = str.replace(/^[=+@-]+/, '').trim();
  }
  return str;
}

/** Extract text content from XML tags */
function parseXmlTags(xml, tagName) {
  const regex = new RegExp(`<${tagName}[^>]*>(.*?)</${tagName}>`, 'gs');
  const matches = [];
  let m;
  while ((m = regex.exec(xml)) !== null) {
    matches.push(m[1]);
  }
  return matches;
}

/**
 * Parse an Excel .xlsx or .zip package.
 * Returns parsed event fields, validation errors by field, and extracted images.
 */
export async function parseExcelOrZipPackage(fileBuffer, fileName = '') {
  const zip = await JSZip.loadAsync(fileBuffer);
  const isZipPackage = !fileName.endsWith('.xlsx') && !zip.file('xl/workbook.xml');

  let xlsxZip = zip;
  let companionImages = new Map();

  if (isZipPackage) {
    // Find .xlsx inside the zip
    const xlsxFileName = Object.keys(zip.files).find(name => name.endsWith('.xlsx') && !name.startsWith('__MACOSX'));
    if (!xlsxFileName) {
      throw new Error('Gói ZIP không chứa file .xlsx hợp lệ.');
    }
    const xlsxData = await zip.files[xlsxFileName].async('arraybuffer');
    xlsxZip = await JSZip.loadAsync(xlsxData);

    // Collect companion images in the root or subfolders
    for (const [pathKey, fileEntry] of Object.entries(zip.files)) {
      if (fileEntry.dir || pathKey.startsWith('__MACOSX')) continue;
      const lower = pathKey.toLowerCase();
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp')) {
        const baseName = pathKey.split('/').pop();
        const imgBlob = await fileEntry.async('blob');
        companionImages.set(baseName.toLowerCase(), imgBlob);
      }
    }
  }

  // 1. Read shared strings if available
  let sharedStrings = [];
  const sstFile = xlsxZip.file('xl/sharedStrings.xml');
  if (sstFile) {
    const sstXml = await sstFile.async('string');
    const siMatches = parseXmlTags(sstXml, 'si');
    sharedStrings = siMatches.map(si => {
      const tMatches = parseXmlTags(si, 't');
      return tMatches.join('');
    });
  }

  // 2. Read sheet1.xml
  const sheetFile = xlsxZip.file('xl/worksheets/sheet1.xml');
  if (!sheetFile) {
    throw new Error('Không tìm thấy bảng tính hợp lệ trong file Excel.');
  }
  const sheetXml = await sheetFile.async('string');

  // Parse rows
  const rowRegex = /<row[^>]*r="(\d+)"[^>]*>(.*?)<\/row>/gs;
  const rows = [];
  let rowMatch;
  while ((rowMatch = rowRegex.exec(sheetXml)) !== null) {
    const rowNum = parseInt(rowMatch[1], 10);
    const rowContent = rowMatch[2];
    // Root-cause fix — every closing tag inside this regex literal MUST
    // escape its own "/" (regex delimiter); `</v>`/`</t>`/`</is>` here were
    // raw, unescaped forward slashes that silently terminated the regex
    // literal early. Rollup's import-analysis parser is what actually
    // caught this (a plain `node --check` run doesn't, since the resulting
    // truncated-regex-then-garbage-tokens still happens to parse as valid,
    // if nonsensical, JS) — this file was never actually imported/built
    // until this pass wired it into CreateEvent.jsx.
    const cellRegex = /<c[^>]*r="([A-Z]+)\d+"(?:[^>]*t="([a-z]+)")?[^>]*>(?:<v>(.*?)<\/v>)?(?:<is><t>(.*?)<\/t><\/is>)?<\/c>/gs;
    const cells = {};
    let cellMatch;
    while ((cellMatch = cellRegex.exec(rowContent)) !== null) {
      const colLetter = cellMatch[1];
      const type = cellMatch[2];
      const val = cellMatch[3];
      const inlineVal = cellMatch[4];
      let finalVal = '';
      if (inlineVal !== undefined) {
        finalVal = inlineVal;
      } else if (type === 's' && val !== undefined) {
        finalVal = sharedStrings[parseInt(val, 10)] || '';
      } else if (val !== undefined) {
        finalVal = val;
      }
      cells[colLetter] = sanitizePlainText(finalVal);
    }
    rows.push({ rowNum, cells });
  }

  // Row 1 is headers, Row 2 is sample or actual data row
  const dataRow = rows.find(r => r.rowNum === 2) || rows[1];
  if (!dataRow) {
    throw new Error('File Excel không có dòng dữ liệu sự kiện.');
  }

  const c = dataRow.cells;

  const rawName = c['A'] || '';
  const rawCat = c['B'] || '';
  const rawDesc = c['C'] || '';
  const rawLoc = c['D'] || '';
  const rawDate = c['E'] || '';
  const rawTime = c['F'] || '';
  const rawPrice = c['G'] || '0';
  const rawCap = c['H'] || '1';

  const inc1Label = c['I'] || '';
  const inc1Detail = c['J'] || '';
  const inc2Label = c['K'] || '';
  const inc2Detail = c['L'] || '';
  const inc3Label = c['M'] || '';
  const inc3Detail = c['N'] || '';

  const rawCoverRef = c['O'] || '';
  const rawAddRefs = c['P'] || '';
  const rawIntro = c['Q'] || '';

  // 3. Extract embedded drawing images if present
  let embeddedImagesByCol = new Map();
  const drawingRelsFile = xlsxZip.file('xl/drawings/_rels/drawing1.xml.rels');
  const drawingFile = xlsxZip.file('xl/drawings/drawing1.xml');
  if (drawingFile && drawingRelsFile) {
    const drawingXml = await drawingFile.async('string');
    const relsXml = await drawingRelsFile.async('string');
    const relRegex = /<Relationship[^>]*Id="([^"]+)"[^>]*Target="([^"]+)"/g;
    const relMap = new Map();
    let rMatch;
    while ((rMatch = relRegex.exec(relsXml)) !== null) {
      let target = rMatch[2].replace(/^\.\.\//, 'xl/');
      relMap.set(rMatch[1], target);
    }

    const anchorRegex = /<xdr:(?:twoCellAnchor|oneCellAnchor)[^>]*>(.*?)<\/xdr:(?:twoCellAnchor|oneCellAnchor)>/gs;
    let aMatch;
    while ((aMatch = anchorRegex.exec(drawingXml)) !== null) {
      const anchorContent = aMatch[1];
      const colMatch = /<xdr:from>.*?<xdr:col>(\d+)<\/xdr:col>/s.exec(anchorContent);
      const blipMatch = /<a:blip[^>]*r:embed="([^"]+)"/s.exec(anchorContent);
      if (colMatch && blipMatch) {
        const colIdx = parseInt(colMatch[1], 10);
        const rId = blipMatch[1];
        const targetPath = relMap.get(rId);
        if (targetPath && xlsxZip.file(targetPath)) {
          const blob = await xlsxZip.file(targetPath).async('blob');
          if (!embeddedImagesByCol.has(colIdx)) embeddedImagesByCol.set(colIdx, []);
          embeddedImagesByCol.get(colIdx).push({ blob, path: targetPath });
        }
      }
    }
  }

  // Also collect any images in xl/media/ if drawings exist but anchors were unmapped
  const mediaFiles = Object.keys(xlsxZip.files).filter(k => k.startsWith('xl/media/'));
  const allMediaBlobs = [];
  for (const mf of mediaFiles) {
    allMediaBlobs.push(await xlsxZip.file(mf).async('blob'));
  }

  // 4. Resolve Cover and Gallery Photos
  let coverImageBlob = null;
  let galleryBlobs = [];

  // Embedded anchor in Col O (index 14)
  if (embeddedImagesByCol.has(14) && embeddedImagesByCol.get(14).length > 0) {
    coverImageBlob = embeddedImagesByCol.get(14)[0].blob;
  }
  // Embedded anchor in Col P (index 15)
  if (embeddedImagesByCol.has(15)) {
    galleryBlobs.push(...embeddedImagesByCol.get(15).map(x => x.blob));
  }

  // If not found in anchors, check companion images or unanchored media
  if (!coverImageBlob) {
    if (rawCoverRef && companionImages.has(rawCoverRef.toLowerCase())) {
      coverImageBlob = companionImages.get(rawCoverRef.toLowerCase());
    } else if (companionImages.size > 0) {
      // First companion image
      const firstKey = Array.from(companionImages.keys())[0];
      coverImageBlob = companionImages.get(firstKey);
    } else if (allMediaBlobs.length > 0) {
      coverImageBlob = allMediaBlobs[0];
      if (allMediaBlobs.length > 1) {
        galleryBlobs.push(...allMediaBlobs.slice(1));
      }
    }
  }

  // Resolve additional images
  if (rawAddRefs && companionImages.size > 0) {
    const names = rawAddRefs.split(',').map(s => s.trim().toLowerCase());
    for (const n of names) {
      if (companionImages.has(n)) {
        galleryBlobs.push(companionImages.get(n));
      }
    }
  }

  // 5. Structure inclusions
  const inclusions = [];
  if (inc1Label.trim()) {
    inclusions.push({ label: inc1Label.trim().slice(0, 60), detail: inc1Detail.trim().slice(0, 300) });
  }
  if (inc2Label.trim()) {
    inclusions.push({ label: inc2Label.trim().slice(0, 60), detail: inc2Detail.trim().slice(0, 300) });
  }
  if (inc3Label.trim()) {
    inclusions.push({ label: inc3Label.trim().slice(0, 60), detail: inc3Detail.trim().slice(0, 300) });
  }

  // 6. Validation
  const errors = {};
  if (!rawName.trim()) {
    errors.name = 'Tên sự kiện không được để trống.';
  }

  const normCat = normalizeCategory(rawCat);

  if (!rawLoc.trim()) {
    errors.location = 'Địa điểm/Khu vực không được để trống.';
  }

  // Date & Time validation
  let parsedDate = rawDate.trim();
  let parsedTime = rawTime.trim();

  // Handle Excel serial date numbers if entered as numbers
  if (/^\d{5}$/.test(parsedDate)) {
    const excelEpoch = new Date(1899, 11, 30);
    const dateObj = new Date(excelEpoch.getTime() + parseInt(parsedDate, 10) * 86400000);
    parsedDate = dateObj.toISOString().slice(0, 10);
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(parsedDate)) {
    errors.event_date = 'Ngày phải có định dạng YYYY-MM-DD (ví dụ: 2026-11-20).';
  } else {
    // Validate not in past
    const [y, m, d] = parsedDate.split('-').map(Number);
    const [hh, mm] = (parsedTime || '19:00').split(':').map(Number);
    const eventTimeMs = new Date(y, m - 1, d, hh || 0, mm || 0).getTime();
    if (eventTimeMs < Date.now() - 5 * 60 * 1000) {
      errors.event_date = 'Ngày giờ sự kiện không thể ở trong quá khứ.';
    }
  }

  if (!parsedTime || !/^\d{1,2}:\d{2}/.test(parsedTime)) {
    errors.event_time = 'Giờ bắt đầu phải có định dạng HH:mm (ví dụ: 19:00).';
  }

  const priceNum = parseInt(rawPrice.replace(/\D/g, ''), 10) || 0;
  if (isNaN(priceNum) || priceNum < 0) {
    errors.price_vnd = 'Giá vé không hợp lệ.';
  }

  const capNum = parseInt(rawCap.replace(/\D/g, ''), 10) || 0;
  if (capNum < 1) {
    errors.capacity = 'Số chỗ ngồi phải từ 1 trở lên.';
  }

  if (!coverImageBlob) {
    errors.cover_image = 'Chưa có ảnh bìa. Hãy chèn ảnh vào ô O hoặc đính kèm ảnh trong file ZIP.';
  }

  const introTrimmed = rawIntro.trim();
  if (introTrimmed.length > 4000) {
    errors.intro = 'Giới thiệu sự kiện tối đa 4000 ký tự.';
  }

  return {
    parsed: {
      name: rawName.trim(),
      categoryKey: normCat.key,
      categoryLabel: normCat.label,
      description: rawDesc.trim(),
      location: rawLoc.trim(),
      eventDate: parsedDate,
      eventTime: parsedTime,
      priceVnd: priceNum,
      capacity: capNum,
      inclusions,
      intro: introTrimmed,
    },
    images: {
      cover: coverImageBlob,
      gallery: galleryBlobs.slice(0, 7), // Max 8 photos total (1 cover + 7 gallery)
    },
    errors,
    isValid: Object.keys(errors).length === 0,
  };
}
