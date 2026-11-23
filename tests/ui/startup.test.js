const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

const css = fs.readFileSync(path.join(__dirname, '../../assets/np-theme.css'), 'utf-8');

const html = `
<!DOCTYPE html>
<html>
<head>
  <style>${css}</style>
</head>
<body data-np-route="startup">
  <div id="app">
    <div class="ContentContainer">
      <div class="StartupContainer___StyledDiv-sc-163imy2-0 sc-163imy2-0">
        <div class="StartupContainer___StyledTitledGreyBox-sc-163imy2-1 sc-163imy2-1 sc-gvsoy-0">
          <div class="TitledGreyBox___StyledDiv2-sc-gvsoy-1 sc-gvsoy-1">
            <p class="TitledGreyBox___StyledP-sc-gvsoy-2">STARTUP COMMAND</p>
          </div>
          <div class="TitledGreyBox___StyledDiv3-sc-gvsoy-4 sc-gvsoy-4">
            <p class="StartupContainer___StyledP-sc-163imy2-3 font-mono">node /home/container/index.js</p>
          </div>
        </div>
        <div class="StartupContainer___StyledTitledGreyBox2-sc-163imy2-4 sc-163imy2-4 sc-gvsoy-0">
          <div class="TitledGreyBox___StyledDiv2-sc-gvsoy-1 sc-gvsoy-1">
            <p class="TitledGreyBox___StyledP-sc-gvsoy-2">DOCKER IMAGE</p>
          </div>
          <div class="TitledGreyBox___StyledDiv3-sc-gvsoy-4 sc-gvsoy-4">
            <select>
              <option>Nodejs 25</option>
            </select>
            <p class="text-neutral-300">This is an advanced feature...</p>
          </div>
        </div>
      </div>
      <h3 class="StartupContainer___StyledH-sc-163imy2-7 sc-163imy2-7">Variables</h3>
      <div class="StartupContainer___StyledDiv3-sc-163imy2-8 sc-163imy2-8">
        <div class="sc-gvsoy-0">
          <div class="sc-gvsoy-1"><p>ADDITIONAL NODE PACKAGES</p></div>
          <div class="sc-gvsoy-4">
            <input type="text" placeholder="Install packages" />
            <p class="text-neutral-300">Install additional node packages</p>
          </div>
        </div>
        <div class="sc-gvsoy-0">
          <div class="sc-gvsoy-1"><p>GIT USERNAME</p></div>
          <div class="sc-gvsoy-4">
            <input type="text" placeholder="Username" />
            <p class="text-neutral-300">Username to auth with git</p>
          </div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
`;

const dom = new JSDOM(html, { runScripts: "dangerously" });
const { window } = dom;
const { document } = window;

function assert(condition, message) {
  if (!condition) {
    console.error('FAIL:', message);
    process.exit(1);
  }
}

const topRow = document.querySelector('.sc-163imy2-0');
const topStyle = window.getComputedStyle(topRow);
assert(topStyle.display === 'flex', 'Top row must be display: flex');
assert(topStyle.flexDirection === 'column', 'Top row must be flex-direction: column (got ' + topStyle.flexDirection + ')');

const cmdCard = document.querySelector('.sc-163imy2-1');
const cmdStyle = window.getComputedStyle(cmdCard);
assert(cmdStyle.width === '100%', 'Startup Command card must be width 100% (got ' + cmdStyle.width + ')');

const dockerCard = document.querySelector('.sc-163imy2-4');
const dockerStyle = window.getComputedStyle(dockerCard);
assert(dockerStyle.width === '100%', 'Docker Image card must be width 100% (got ' + dockerStyle.width + ')');
assert(dockerStyle.marginLeft === '0px', 'Docker Image card must have marginLeft 0px (got ' + dockerStyle.marginLeft + ')');

const cmdText = document.querySelector('.StartupContainer___StyledP-sc-163imy2-3');
const cmdTextStyle = window.getComputedStyle(cmdText);
assert(cmdTextStyle.textTransform === 'none', 'Startup Command text must be textTransform: none (got ' + cmdTextStyle.textTransform + ')');

const varsGrid = document.querySelector('.sc-163imy2-8');
const varsGridStyle = window.getComputedStyle(varsGrid);
assert(varsGridStyle.display === 'grid', 'Variables must be display: grid (got ' + varsGridStyle.display + ')');
assert(varsGridStyle.gridTemplateColumns.includes('repeat(2, minmax(0'), 'Variables must have 2-column grid template (got ' + varsGridStyle.gridTemplateColumns + ')');

const varCard = document.querySelector('.sc-163imy2-8 .sc-gvsoy-0');
const varCardStyle = window.getComputedStyle(varCard);
assert(varCardStyle.borderWidth !== '0px', 'Variable card must have border');

console.log('✔ All Startup page layout assertions passed successfully!');
