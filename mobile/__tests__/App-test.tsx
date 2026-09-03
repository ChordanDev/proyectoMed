import { render } from '@testing-library/react-native';
import App from '../App';

describe('<App />', () => {
  it('renders without crashing', async () => {
    const { toJSON, getByText } = await render(<App />);
    // The default Expo StatusBar demo renders a Text node with a prompt message.
    expect(toJSON()).toBeTruthy();
    expect(getByText(/Open up App\.tsx/)).toBeTruthy();
  });
});