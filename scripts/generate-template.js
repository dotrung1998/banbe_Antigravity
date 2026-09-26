import fs from 'fs';
import path from 'path';
import JSZip from 'jszip';

export async function createBanbeEventTemplateXlsx() {
  const zip = new JSZip();

  // [Content_Types].xml
  zip.file('[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedString+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>`);

  // _rels/.rels
  zip.file('_rels/.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>`);

  // xl/_rels/workbook.xml.rels
  zip.file('xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>`);

  // xl/workbook.xml
  zip.file('xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Banbe Events" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>`);

  // xl/styles.xml
  zip.file('xl/styles.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Arial"/></font>
    <font><b/><sz val="11"/><name val="Arial"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <borders count="1">
    <border><left/><right/><top/><bottom/></border>
  </borders>
  <cellStyleXfs count="1">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
  </cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
  </cellXfs>
</styleSheet>`);

  // Data rows
  const headers = [
    'name', 'category', 'description', 'location', 'event_date', 'event_time',
    'price_vnd', 'capacity',
    'included_1_label', 'included_1_detail',
    'included_2_label', 'included_2_detail',
    'included_3_label', 'included_3_detail',
    'cover_image', 'additional_images'
  ];

  const sampleRow = [
    'Bếp Nhỏ №15',
    'supper',
    'Mười bốn chỗ. Một ga-ra cải tạo ở Bình Thạnh. Minh nấu món gì chợ sáng có.',
    'Bình Thạnh',
    '2026-11-20',
    '19:00',
    '900000',
    '14',
    '5 món',
    'Thực đơn 5 món nướng theo mùa',
    'Rượu vang',
    'Một ly vang đỏ chọn lọc',
    'Tráng miệng',
    'Bánh ngọt thủ công',
    'cover.jpg',
    'photo1.jpg, photo2.jpg'
  ];

  const instructions = [
    'Bắt buộc (*)',
    'supper / fashion / gallery / music / popup (*)',
    'Tuỳ chọn',
    'Khu vực: Quận 1, Bình Thạnh, Thảo Điền... (*)',
    'YYYY-MM-DD tương lai (*)',
    'HH:mm (*)',
    'Số tiền VNĐ (0 nếu miễn phí) (*)',
    'Số lượng >= 1 (*)',
    'Tên ngắn món/dịch vụ 1 (tối đa 60 ký tự)',
    'Giải thích món 1 (tối đa 300 ký tự)',
    'Tên ngắn món/dịch vụ 2',
    'Giải thích món 2',
    'Tên ngắn món/dịch vụ 3',
    'Giải thích món 3',
    'Chèn ảnh trực tiếp vào ô này HOẶC ghi tên file ảnh (ví dụ cover.jpg) (*)',
    'Chèn ảnh trực tiếp HOẶC danh sách tên file cách nhau bằng dấu phẩy'
  ];

  // Shared strings
  const strings = [];
  const stringIndexMap = new Map();
  function getStringIndex(str) {
    if (stringIndexMap.has(str)) return stringIndexMap.get(str);
    const idx = strings.length;
    strings.push(str);
    stringIndexMap.set(str, idx);
    return idx;
  }

  function getColLetter(colIdx) {
    let letter = '';
    while (colIdx >= 0) {
      letter = String.fromCharCode((colIdx % 26) + 65) + letter;
      colIdx = Math.floor(colIdx / 26) - 1;
    }
    return letter;
  }

  const rows = [headers, sampleRow, instructions];
  let sheetXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheetData>`;

  rows.forEach((row, rIdx) => {
    const rowNum = rIdx + 1;
    sheetXml += `<row r="${rowNum}">`;
    row.forEach((cellVal, cIdx) => {
      const cellRef = `${getColLetter(cIdx)}${rowNum}`;
      if (typeof cellVal === 'number' || (/^\d+$/.test(cellVal) && cIdx === 6 || cIdx === 7)) {
        sheetXml += `<c r="${cellRef}"><v>${cellVal}</v></c>`;
      } else {
        const sIdx = getStringIndex(cellVal);
        const style = rIdx === 0 ? ' s="1"' : '';
        sheetXml += `<c r="${cellRef}" t="s"${style}><v>${sIdx}</v></c>`;
      }
    });
    sheetXml += `</row>`;
  });

  sheetXml += `</sheetData>
</worksheet>`;

  zip.file('xl/worksheets/sheet1.xml', sheetXml);

  let sstXml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${strings.length}" uniqueCount="${strings.length}">`;
  strings.forEach(s => {
    const escaped = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    sstXml += `<si><t>${escaped}</t></si>`;
  });
  sstXml += `</sst>`;
  zip.file('xl/sharedStrings.xml', sstXml);

  return await zip.generateAsync({ type: 'nodebuffer' });
}

async function main() {
  const buf = await createBanbeEventTemplateXlsx();
  fs.mkdirSync('public/templates', { recursive: true });
  fs.writeFileSync('public/templates/banbe_event_template.xlsx', buf);
  fs.mkdirSync('apps/ios/BanbeApp/Resources', { recursive: true });
  fs.writeFileSync('apps/ios/BanbeApp/Resources/banbe_event_template.xlsx', buf);
  console.log('Successfully generated banbe_event_template.xlsx in public/templates and apps/ios/BanbeApp/Resources!');
}

main().catch(console.error);
