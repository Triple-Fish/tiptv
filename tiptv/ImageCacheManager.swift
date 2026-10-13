import Foundation
import ImageIO
import UIKit

// MARK: - In-Memory & Network Artwork Cache

final class ImageCacheManager: @unchecked Sendable {
  static let shared = ImageCacheManager()

  private let cache = NSCache<NSURL, UIImage>()
  private let session: URLSession
  private let lock = NSLock()
  private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]
  private var failedURLs: [URL: Date] = [:]
  private let failedURLRetryInterval: TimeInterval = 5 * 60

  private init() {
    cache.countLimit = 1200
    cache.totalCostLimit = 60 * 1024 * 1024  // 60MB RAM limit
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 5
    config.timeoutIntervalForResource = 8
    config.httpMaximumConnectionsPerHost = 4
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.urlCache = URLCache.shared
    self.session = URLSession(configuration: config)

    #if canImport(UIKit)
      NotificationCenter.default.addObserver(
        forName: UIApplication.didReceiveMemoryWarningNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.cache.removeAllObjects()
        self?.lock.withLock {
          self?.failedURLs.removeAll(keepingCapacity: true)
        }
      }
    #endif
  }

  func image(for url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  func isFailed(url: URL) -> Bool {
    lock.withLock {
      guard let failureDate = failedURLs[url] else { return false }
      if Date().timeIntervalSince(failureDate) < failedURLRetryInterval {
        return true
      }
      failedURLs.removeValue(forKey: url)
      return false
    }
  }

  func setImage(_ image: UIImage, for url: URL) {
    let cost = Int(image.size.width * image.size.height * 4)
    cache.setObject(image, forKey: url as NSURL, cost: cost)
  }

  func loadImage(from url: URL) async -> UIImage? {
    if let cached = image(for: url) {
      return cached
    }
    if isFailed(url: url) {
      return nil
    }

    let task: Task<UIImage?, Never> = lock.withLock {
      if let existingTask = inFlightTasks[url] {
        return existingTask
      }

      let newTask = Task<UIImage?, Never> { [session] in
        defer {
          self.lock.withLock {
            _ = self.inFlightTasks.removeValue(forKey: url)
          }
        }

        do {
          var request = URLRequest(url: url)
          request.setValue(XtreamService.defaultUserAgent, forHTTPHeaderField: "User-Agent")
          let (data, response) = try await session.data(for: request)
          guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode),
            let uiImage = downsample(data: data, to: 300) ?? UIImage(data: data)
          else {
            markFailed(url)
            return nil
          }
          self.setImage(uiImage, for: url)
          return uiImage
        } catch is CancellationError {
          return nil
        } catch let urlError as URLError where urlError.code == .cancelled {
          return nil
        } catch {
          markFailed(url)
          return nil
        }
      }
      inFlightTasks[url] = newTask
      return newTask
    }

    return await task.value
  }

  private func markFailed(_ url: URL) {
    lock.withLock {
      failedURLs[url] = Date()
      if failedURLs.count > 5_000 {
        failedURLs.removeAll(keepingCapacity: true)
      }
    }
  }

  private func downsample(data: Data, to maxPixelSize: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [
      kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
      return nil
    }
    let downsampleOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    guard
      let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source, 0, downsampleOptions as CFDictionary)
    else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }
}
