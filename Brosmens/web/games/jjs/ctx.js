// Общий контекст игры (заполняется в main.js). Все модули импортируют G отсюда.
export const G = {
  scene: null, camera: null, renderer: null,
  world: null, fx: null, hud: null, chat: null, ctl: null, ui: null,
  fighters: [],
  tasks: [],
  time: 0,
  player: null,
  matchOver: false,
  addTask(fn) { this.tasks.push(fn); },
  // Клод и игрок — союзники в FFA
  isAlly(a, b) {
    if (a === b) return true;
    return (a.isPlayer && b.isClaude) || (a.isClaude && b.isPlayer);
  },
  shake() {}, sound() {}, botEvent() {}, onKill() {},
};
