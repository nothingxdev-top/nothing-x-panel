const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

const css = fs.readFileSync(path.join(__dirname, '../../assets/np-theme.css'), 'utf-8');
const js = fs.readFileSync(path.join(__dirname, '../../assets/np-theme.js'), 'utf-8');

const html = `
<!DOCTYPE html>
<html>
<head>
  <style>${css}</style>
</head>
<body data-np-route="files">
  <div id="app">
    <div class="relative">
      <div class="CodemirrorEditor___StyledDiv-sc-163imy2-0 CodemirrorEditor" style="min-height: 16rem; height: 500px;">
        <textarea style="display:none;"># Test Markdown</textarea>
        <div class="CodeMirror cm-s-ayu-mirage" style="height: 100%;">
          <div class="CodeMirror-scroll">
            <div class="CodeMirror-line"><span># Test Markdown</span></div>
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
`;

const dom = new JSDOM(html, {
  url: "https://panel.fayas.nx.kg/server/919b1390/files/edit#/README.md",
  runScripts: "dangerously"
});
const { window } = dom;
const { document } = window;

// Inject theme JS
window.eval(js);

function assert(condition, message) {
  if (!condition) {
    console.error('FAIL:', message);
    process.exit(1);
  }
}

const toolbar = document.getElementById('np-md-toolbar');
assert(toolbar, 'Markdown toolbar should be mounted for README.md');

const editor = document.querySelector('div[class*="CodemirrorEditor"]');
assert(editor, 'Editor container should exist');

assert(editor.previousElementSibling === toolbar, 'Toolbar must be the preceding sibling of the editor container, NOT inside it!');

const btnEdit = document.getElementById('np-md-btn-edit');
const btnPreview = document.getElementById('np-md-btn-preview');
const previewCont = document.getElementById('np-md-preview-container');

assert(btnEdit && btnPreview && previewCont, 'Buttons and preview container must exist');
assert(previewCont.style.display === 'none', 'Preview container should initially be hidden in edit mode');
assert(editor.style.display !== 'none', 'Editor container should initially be visible in edit mode');

// Test click preview
btnPreview.click();
assert(previewCont.style.display === 'block', 'Preview container should be visible after clicking preview');
assert(editor.style.display === 'none', 'Editor container should be hidden after clicking preview');
assert(previewCont.innerHTML.includes('<h1'), 'Markdown # should render as <h1> in preview');

// Test click edit
btnEdit.click();
assert(previewCont.style.display === 'none', 'Preview container should be hidden after clicking edit');
assert(editor.style.display === 'block', 'Editor container should be visible after clicking edit');

console.log('✔ All Markdown editor & preview tests passed successfully!');
