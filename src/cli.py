import argparse
import asyncio
import os
from dotenv import load_dotenv
from src.agent.browser.config import BrowserConfig
from src.providers.google import ChatGoogle
from src.agent import Agent

async def main():
    parser = argparse.ArgumentParser(description="Web-Use CLI Wrapper")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--query", type=str, help="The task for the browsing agent to perform")
    group.add_argument("--file", type=str, help="Path to a text file containing the query/masterprompt")
    parser.add_argument("--headless", action="store_true", help="Run browser in headless mode")
    parser.add_argument("--steps", type=int, default=100, help="Maximum number of steps")
    args = parser.parse_args()

    query = args.query
    if args.file:
        if not os.path.exists(args.file):
            print(f"[!] Error: File '{args.file}' not found.")
            return
        with open(args.file, "r") as f:
            query = f.read()

    load_dotenv()

    # Initialize the LLM (using Gemini as the default provider in this environment)
    llm = ChatGoogle(model='gemini-2.5-flash')
    
    # Configure the browser
    config = BrowserConfig(
        browser='chrome', 
        headless=args.headless,
        use_system_profile=True
    )
    
    # Initialize the agent
    agent = Agent(
        config=config, 
        llm=llm, 
        use_vision=True, # Enable vision for better accuracy in skills
        use_web_mcp=True, 
        max_steps=args.steps, 
        keep_alive=False # Close after task completion for skill usage
    )
    
    # Execute the query
    print(f"[*] Starting Web-Use Agent with query: {query}")
    await agent.ainvoke(query)
    
    # Print the final summary
    if agent.state.messages:
        last_msg = agent.state.messages[-1]
        if hasattr(last_msg, 'content'):
            print("\n[+] Final Agent Response:")
            print(last_msg.content)

if __name__ == "__main__":
    asyncio.run(main())
