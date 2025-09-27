use crossterm::{
    event::{self, Event, KeyCode},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    layout::{Constraint, Direction, Layout},
    style::{Color, Style},
    Terminal,
};
use std::io::{self, BufRead};
use tokio::{io::AsyncBufReadExt, process::{Command, Stdio}, time::{sleep, Duration}};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Terminal setup (like React mount)
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // State (like React useState)
    let mut state = AppState::default();

    loop {
        terminal.draw(|f| draw_ui(f, &mut state))?;

        if let Event::Key(key) = event::read()? {
            match key.code {
                KeyCode::Char('q') => break,
                KeyCode::Down => state.selected = state.selected.saturating_add(1).min(2),
                KeyCode::Up => state.selected = state.selected.saturating_sub(1),
                KeyCode::Enter => {
                    state.installing = true;
                    run_install(&mut state).await?;  // Async with progress updates
                    break;
                }
                _ => {},
            }
        }
    }

    // Cleanup (like unmount)
    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    Ok(())
}

// State
#[derive(Default)]
struct AppState {
    selected: usize,
    installing: bool,
    current_step: String,  // "Step X/7: Desc" or error
    model_choice: usize,  // 0: phi3-mini, 1: custom
    custom_url: String,   // For input
}

// Run install async (spawn like Node child_process)
async fn run_install(state: &mut AppState) -> Result<(), io::Error> {
    let version = match state.selected {
        0 => "master",
        1 => "v1.0",
        _ => "custom-tag",  // Add prompt if needed
    };
    let mut child = Command::new("bash")
        .arg("/home/survon/install.sh")  // Assume path; adjust for production
        .arg("--version").arg(version)
        .arg(if state.model_choice == 0 { "--model=1" } else { format!("--custom-url={}", state.custom_url) })
        .stdout(Stdio::piped())
        .spawn()?;

    // Read stdout async (like stdout.on('data') in Node)
    let stdout = child.stdout.take().unwrap();
    let mut lines = tokio::io::BufReader::new(stdout).lines();
    while let Some(line) = lines.next_line().await? {
        if line.starts_with("PROGRESS:") {
            state.current_step = line.replace("PROGRESS:", "");  // Update state like setState
        } else if line.starts_with("ERROR:") {
            state.current_step = format!("Error: {}", line.replace("ERROR:", ""));
            break;
        }
        sleep(Duration::from_millis(100)).await;  // Throttle redraws
    }
    child.wait().await?;
    Ok(())
}

// Draw TUI
fn draw_ui(f: &mut ratatui::Frame, state: &mut AppState) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(0), Constraint::Length(3)])
        .split(f.area());

    let logo = Paragraph::new("Survon OS Installer\nOff-Grid Resilience")
        .block(Block::default().title("Welcome").borders(Borders::ALL))
        .style(Style::default().fg(Color::Green));
    f.render_widget(logo, chunks[0]);

    let items = vec![
        ListItem::new("Latest (Master)"),
        ListItem::new("Release v1.0"),
        ListItem::new("Custom (Enter Tag)"),
    ];
    let list = List::new(items)
        .block(Block::default().title("Select Version").borders(Borders::ALL))
        .highlight_style(Style::default().fg(Color::Yellow));
    let mut list_state = ListState::default().with_selected(Some(state.selected));
    f.render_stateful_widget(list, chunks[1], &mut list_state);

    if state.installing {
        let progress = Paragraph::new(state.current_step.clone())
            .block(Block::default().title("Progress").borders(Borders::ALL))
            .style(Style::default().fg(Color::Cyan));
        f.render_widget(progress, chunks[2]);
    } else {
        state.model_choice = state.selected;
        if state.model_choice == 1 {  // Custom
            // Simple input loop (or TextArea widget for full TUI)
            println!("Enter URL: ");  // Or integrate ratatui input
            let mut input = String::new();
            io::stdin().read_line(&mut input)?;
            state.custom_url = input.trim().to_string();
        }
        run_install(state).await?;
    }
}
