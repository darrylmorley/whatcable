import database from './cabledb.js';
const unique = (values) => [...new Set(values)];
const records = database.list.map((cable, index) => {
  const speed = (cable.speed.match(/\(([^)]+)\)/)?.[1] || cable.speed).split(',')[0];
  const power = cable.power.match(/~?\d+\s*W/)?.[0].replace(/\s*/g, '').replace('W', ' W') || cable.power;
  const speedNumber = Math.max(...(speed.match(/[\d.]+/g) || ['0']).map(Number)) / (speed.includes('Mbps') ? 1000 : 1);
  return { ...cable, index, speedLabel: speed, powerLabel: power, speedNumber,
    powerNumber: Number(power.replace(/[^\d.]/g, '')),
    search: Object.values(cable).join(' ').toLowerCase() };
});
export default {
  records,
  speeds: unique(records.map(c => c.speedLabel)),
  powers: unique(records.map(c => c.powerLabel)).sort((a,b)=>parseFloat(a.replace('~',''))-parseFloat(b.replace('~','')))
};
