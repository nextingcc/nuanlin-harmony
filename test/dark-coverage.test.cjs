const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const PAGES = path.join(__dirname, '../entry/src/main/ets/pages');
const DARK_PAGES = [
  'Home', 'Tools', 'Assistant', 'Breathe', 'Memo', 'Notifications',
  'Settings', 'Profile', 'ResidentList', 'CareList', 'FollowupQueue',
  'Followup', 'FollowupList', 'FollowupRecord', 'Interview', 'Journal',
  'PersonForm', 'ImportPerson', 'Login', 'ResidenceEdit', 'MapLocation', 'CommunicationPreferences', 'VisitPlan'
];

test('pages documented as dark-capable subscribe to darkMode and use the palette', () => {
  for (const name of DARK_PAGES) {
    const file = path.join(PAGES, `${name}.ets`);
    const text = fs.readFileSync(file, 'utf8');
    assert.ok(text.includes("@StorageProp('darkMode')"), `${name} does not subscribe to darkMode`);
    assert.ok(text.includes('palette('), `${name} does not use palette()`);
  }
});

test('new page files must be listed in the dark coverage check', () => {
  const files = fs.readdirSync(PAGES).filter(f => f.endsWith('.ets'));
  const unlisted = files.filter(f => {
    const name = f.replace(/\.ets$/, '');
    return !DARK_PAGES.includes(name) && fs.readFileSync(path.join(PAGES, f), 'utf8').includes("@StorageProp('darkMode')");
  });
  assert.deepEqual(unlisted, [], 'dark-capable page missing from DARK_PAGES: ' + unlisted.join(', '));
});


