// Top-level shell — tablet frame, top bar, current screen, bottom nav.
import { useState } from 'react';
import { TopBar, BottomNav } from './components/primitives.jsx';
import { HomeScreen }      from './screens/HomeScreen.jsx';
import { TVScreen }        from './screens/TVScreen.jsx';
import { PersonScreen }    from './screens/PersonScreen.jsx';
import { RemindersScreen } from './screens/RemindersScreen.jsx';

export const App = () => {
  const [screen, setScreen] = useState("home");

  const greetings = {
    home: "Good morning",
    tv: "Watching",
    people: "Looking",
    reminders: "Today",
  };

  const Screen = {
    home:      HomeScreen,
    tv:        TVScreen,
    people:    PersonScreen,
    reminders: RemindersScreen,
  }[screen];

  return (
    <div className="tablet-stage">
      <div className="tablet">
        <TopBar
          greeting={greetings[screen]}
          time="8:42"
          day="TUE"
          listening={false}
        />
        <Screen goTo={setScreen} />
        <BottomNav current={screen} onChange={setScreen} />
      </div>
    </div>
  );
};
