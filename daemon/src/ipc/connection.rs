use anyhow::Result;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use super::types::{JsonRpcNotification, JsonRpcRequest, JsonRpcResponse};

pub struct Connection {
    reader: BufReader<tokio::io::ReadHalf<UnixStream>>,
    writer: tokio::io::WriteHalf<UnixStream>,
}

impl Connection {
    pub fn new(stream: UnixStream) -> Self {
        let (read_half, write_half) = tokio::io::split(stream);
        Self {
            reader: BufReader::new(read_half),
            writer: write_half,
        }
    }

    pub async fn read_request(&mut self) -> Result<Option<JsonRpcRequest>> {
        let mut line = String::new();
        let n = self.reader.read_line(&mut line).await?;
        if n == 0 {
            return Ok(None); // EOF
        }
        let req: JsonRpcRequest = serde_json::from_str(line.trim())?;
        Ok(Some(req))
    }

    pub async fn write_response(&mut self, response: &JsonRpcResponse) -> Result<()> {
        let mut data = serde_json::to_string(response)?;
        data.push('\n');
        self.writer.write_all(data.as_bytes()).await?;
        self.writer.flush().await?;
        Ok(())
    }

    pub async fn write_notification(&mut self, notification: &JsonRpcNotification) -> Result<()> {
        let mut data = serde_json::to_string(notification)?;
        data.push('\n');
        self.writer.write_all(data.as_bytes()).await?;
        self.writer.flush().await?;
        Ok(())
    }
}
