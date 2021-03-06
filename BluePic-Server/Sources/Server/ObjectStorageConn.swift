/**
* Copyright IBM Corporation 2016
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import Foundation
import BluemixObjectStorage
import LoggerAPI
import Dispatch

public struct ObjectStorageConn {
  let connectQueue = dispatch_queue_create("connectQueue", nil)
  let objStorage: ObjectStorage
  let connProps: ObjectStorageConnProps
  private var authenticated: Bool = false
  private var lastAuthenticatedTs: NSDate?

  init(objStorageConnProps: ObjectStorageConnProps) {
    connProps = objStorageConnProps
    objStorage = ObjectStorage(projectId: connProps.projectId)
  }

  mutating func getObjectStorage(completionHandler: (objStorage: ObjectStorage?) -> Void) {
    Log.verbose("Starting task in serialized block (getting ObjectStorage instance)...")
    dispatch_sync(connectQueue) {
      self.connect(completionHandler: completionHandler)
    }
    Log.verbose("Completed task in serialized block.")
    let param: ObjectStorage? = (authenticated) ? objStorage : nil
    completionHandler(objStorage: param)
  }

  private mutating func connect(completionHandler: (objStorage: ObjectStorage?) -> Void) {
    Log.verbose("Determining if we have an ObjectStorage instance ready to use...")
    if authenticated, let lastAuthenticatedTs = lastAuthenticatedTs {
      // Check when was the last time we got an auth token
      // If it's been less than 50 mins, then reuse auth token.
      // This logic is just a stopgap solution to avoid requesting a new
      // authToken for every ObjectStorage request.
      // The ObjectStorage SDK will contain logic for handling expired authToken
      let timeDiff: NSTimeInterval = lastAuthenticatedTs.timeIntervalSinceNow
      let minsDiff = Int(fabs(timeDiff / 60))
      if minsDiff < 50 {
        Log.verbose("Reusing existing Object Storage auth token...")
        return
      }
    }

    // Network call should be synchronous since we need to know the result before
    // proceeding...
    let semaphore = dispatch_semaphore_create(0)
    Log.verbose("Making network call synchronous...")
    objStorage.connect(userId: connProps.userId, password: connProps.password, region: ObjectStorage.REGION_DALLAS) { (error) in
      if let error = error {
        let errorMsg = "Could not connect to Object Storage."
        Log.error("\(errorMsg) Error was: '\(error)'.")
        self.authenticated = false
      } else {
        Log.verbose("Successfully obtained authentication token for Object Storage.")
        self.authenticated = true
        self.lastAuthenticatedTs = NSDate()
        Log.verbose("lastAuthenticatedTs is \(self.lastAuthenticatedTs).")
      }
      Log.verbose("Signaling semaphore...")
      dispatch_semaphore_signal(semaphore)
    }
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    Log.verbose("Continuing execution after synchronous network call...")
  }

}
